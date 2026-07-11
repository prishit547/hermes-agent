"""Realtime new-mail notifier — IMAP IDLE → ntfy push.

Holds an **outbound** IMAP connection to the mail server and uses IMAP IDLE so
the server pushes new-mail notifications to us in near-real-time. On each new
message it publishes a short alert (sender + subject) to the ntfy topic the
mobile app streams from — so a new email pops up on the phone within seconds,
with **nothing exposed to the internet** (the connection is outbound-only).

This is deliberately dumb: it only *notifies*. Reading/drafting/sending happen in
the app via the ``/api/email/*`` endpoints (IMAP/SMTP). Run it alongside the
gateway:

    nohup ./venv/bin/python -m tools.email_notifier > ~/.hermes/email_notifier.log 2>&1 &

Config (from ``~/.hermes/.env``): EMAIL_ADDRESS, EMAIL_APP_PASSWORD,
EMAIL_IMAP_HOST (default imap.gmail.com), NTFY_SERVER_URL, NTFY_TOPIC.
"""

from __future__ import annotations

import email as email_lib
import imaplib
import json
import logging
import os
import socket
import time
import urllib.request
from email.header import decode_header, make_header
from email.utils import parseaddr

logger = logging.getLogger("email_notifier")

# Re-issue IDLE well before the RFC-2177 29-minute server limit.
_IDLE_KEEPALIVE = 600  # seconds
_RECONNECT_BACKOFF_MAX = 60


def _load_env() -> None:
    try:
        from hermes_cli.env_loader import load_hermes_dotenv
        load_hermes_dotenv()
    except Exception:
        pass


def _cfg() -> dict:
    return {
        "address": (os.getenv("EMAIL_ADDRESS") or os.getenv("EMAIL_USER") or "").strip(),
        "password": (os.getenv("EMAIL_APP_PASSWORD") or os.getenv("EMAIL_PASSWORD") or "").strip(),
        "imap_host": os.getenv("EMAIL_IMAP_HOST", "imap.gmail.com").strip(),
        "imap_port": int(os.getenv("EMAIL_IMAP_PORT", "993") or 993),
        "ntfy_server": (os.getenv("NTFY_SERVER_URL", "https://ntfy.sh") or "").rstrip("/"),
        "ntfy_topic": (os.getenv("NTFY_TOPIC") or os.getenv("NTFY_HOME_CHANNEL") or "").strip(),
    }


def _dh(value: str) -> str:
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def _publish(cfg: dict, title: str, body: str) -> None:
    """Publish to ntfy via JSON (handles unicode cleanly)."""
    if not cfg["ntfy_topic"]:
        return
    payload = json.dumps({
        "topic": cfg["ntfy_topic"],
        "title": title[:200] or "New email",
        "message": body[:400],
        "tags": ["email"],
    }).encode("utf-8")
    req = urllib.request.Request(
        cfg["ntfy_server"], data=payload, method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        urllib.request.urlopen(req, timeout=15).read()
    except Exception as exc:
        logger.warning("ntfy publish failed: %s", exc)


class _Notifier:
    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.imap = None
        self.watermark = 0

    def connect(self) -> None:
        c = self.cfg
        self.imap = imaplib.IMAP4_SSL(c["imap_host"], c["imap_port"])
        self.imap.login(c["address"], c["password"])
        self.imap.select("INBOX")
        typ, data = self.imap.uid("search", None, "ALL")
        uids = data[0].split() if data and data[0] else []
        self.watermark = int(uids[-1]) if uids else 0
        logger.info("Connected to %s as %s (watermark uid=%s)",
                    c["imap_host"], c["address"], self.watermark)

    def _idle_wait(self, timeout: int) -> bool:
        """Enter IDLE and block until the server signals new mail or [timeout]."""
        M = self.imap
        tag = M._new_tag()
        M.send(b"%s IDLE\r\n" % tag)
        # Consume the '+ idling' continuation line.
        resp = M.readline()
        if not resp.startswith(b"+"):
            resp = M.readline()
        activity = False
        M.sock.settimeout(timeout)
        try:
            while True:
                line = M.readline()
                if not line:
                    break
                if b"EXISTS" in line or b"RECENT" in line:
                    activity = True
                    break
        except (socket.timeout, OSError):
            pass
        finally:
            M.sock.settimeout(None)
            try:
                M.send(b"DONE\r\n")
                while True:
                    line = M.readline()
                    if not line or line.startswith(tag):
                        break
            except Exception:
                pass
        return activity

    def _notify_new(self) -> None:
        M = self.imap
        typ, data = M.uid("search", None, f"UID {self.watermark + 1}:*")
        uids = [u for u in (data[0].split() if data and data[0] else []) if int(u) > self.watermark]
        for uid in uids:
            try:
                typ, d = M.uid("fetch", uid, "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])")
                if not d or not isinstance(d[0], tuple):
                    continue
                msg = email_lib.message_from_bytes(d[0][1])
                name, addr = parseaddr(_dh(msg.get("From", "")))
                sender = name or addr or "New email"
                subject = _dh(msg.get("Subject", "")) or "(no subject)"
                _publish(self.cfg, title=sender, body=subject)
                logger.info("Notified: %s — %s", sender, subject)
            except Exception as exc:
                logger.warning("Failed to process uid %s: %s", uid, exc)
            finally:
                self.watermark = max(self.watermark, int(uid))

    def run(self) -> None:
        backoff = 2
        while True:
            try:
                self.connect()
                backoff = 2
                while True:
                    if self._idle_wait(_IDLE_KEEPALIVE):
                        self._notify_new()
            except Exception as exc:
                logger.warning("Notifier connection error: %s (reconnecting in %ss)", exc, backoff)
                try:
                    if self.imap:
                        self.imap.logout()
                except Exception:
                    pass
                time.sleep(backoff)
                backoff = min(backoff * 2, _RECONNECT_BACKOFF_MAX)


_bg_thread = None


def start_background() -> bool:
    """Start the IMAP-IDLE notifier in a daemon thread (idempotent).

    Called by the gateway's api_server on boot and whenever email is (re)connected
    via ``/api/email/config`` — so the user never runs this process manually.
    Returns True if a watcher is running, False if email isn't configured yet.
    """
    global _bg_thread
    import threading

    _load_env()
    cfg = _cfg()
    if not (cfg["address"] and cfg["password"] and cfg["ntfy_topic"]):
        return False
    if _bg_thread is not None and _bg_thread.is_alive():
        return True

    def _run():
        try:
            _Notifier(cfg).run()
        except Exception:
            logger.exception("email notifier thread crashed")

    _bg_thread = threading.Thread(target=_run, name="email-idle-notifier", daemon=True)
    _bg_thread.start()
    logger.info("email IMAP-IDLE notifier started in-process for %s", cfg["address"])
    return True


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    _load_env()
    cfg = _cfg()
    if not (cfg["address"] and cfg["password"]):
        print("✗ EMAIL_ADDRESS and EMAIL_APP_PASSWORD must be set in ~/.hermes/.env")
        raise SystemExit(1)
    if not cfg["ntfy_topic"]:
        print("✗ NTFY_TOPIC (or NTFY_HOME_CHANNEL) must be set in ~/.hermes/.env")
        raise SystemExit(1)
    print(f"✓ Watching {cfg['address']} — new mail → ntfy topic {cfg['ntfy_topic']}")
    _Notifier(cfg).run()


if __name__ == "__main__":
    main()
