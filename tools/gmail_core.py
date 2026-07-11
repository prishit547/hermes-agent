"""Email operations over IMAP/SMTP, shared by the ``gmail`` agent tool and the
api_server ``/api/email/*`` endpoints.

All-IMAP path (one Google **App Password**, no OAuth): reads via IMAP, sends via
SMTP, drafts via IMAP APPEND. Configured from ``~/.hermes/.env``:

    EMAIL_ADDRESS=you@gmail.com
    EMAIL_APP_PASSWORD=<16-char Google App Password>
    # optional (defaults are Gmail):
    EMAIL_IMAP_HOST=imap.gmail.com   EMAIL_IMAP_PORT=993
    EMAIL_SMTP_HOST=smtp.gmail.com   EMAIL_SMTP_PORT=587

Returns plain dicts/lists ready to serialize to JSON. Raises ``GmailError`` (kept
under that name so callers don't change) on any failure so the caller can surface
a friendly message.
"""

from __future__ import annotations

import email as email_lib
import imaplib
import logging
import smtplib
import time
from email.header import decode_header, make_header
from email.mime.text import MIMEText
from email.utils import parseaddr
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

DRAFTS_MAILBOX = "[Gmail]/Drafts"


class GmailError(Exception):
    """Raised when email is unconfigured or an IMAP/SMTP call fails."""


def _cfg() -> Dict[str, Any]:
    import os
    return {
        "address": (os.getenv("EMAIL_ADDRESS") or os.getenv("EMAIL_USER") or "").strip(),
        "password": (os.getenv("EMAIL_APP_PASSWORD") or os.getenv("EMAIL_PASSWORD") or "").strip(),
        "imap_host": os.getenv("EMAIL_IMAP_HOST", "imap.gmail.com").strip(),
        "imap_port": int(os.getenv("EMAIL_IMAP_PORT", "993") or 993),
        "smtp_host": os.getenv("EMAIL_SMTP_HOST", "smtp.gmail.com").strip(),
        "smtp_port": int(os.getenv("EMAIL_SMTP_PORT", "587") or 587),
    }


def is_configured() -> bool:
    c = _cfg()
    return bool(c["address"] and c["password"])


def _require_config() -> Dict[str, Any]:
    c = _cfg()
    if not (c["address"] and c["password"]):
        raise GmailError(
            "Email is not connected. Add EMAIL_ADDRESS and EMAIL_APP_PASSWORD to "
            "~/.hermes/.env (a Google App Password), then restart the gateway."
        )
    return c


def _imap(readonly: bool = True):
    c = _require_config()
    try:
        M = imaplib.IMAP4_SSL(c["imap_host"], c["imap_port"])
        M.login(c["address"], c["password"])
        M.select("INBOX", readonly=readonly)
        return M
    except imaplib.IMAP4.error as exc:
        raise GmailError(f"IMAP login failed: {exc}") from exc
    except Exception as exc:
        raise GmailError(f"Could not connect to IMAP: {exc}") from exc


def _logout(M) -> None:
    try:
        M.logout()
    except Exception:
        pass


def _dh(value: str) -> str:
    """Decode a possibly RFC2047-encoded header to a plain string."""
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def _split_addr(raw: str) -> Dict[str, str]:
    name, addr = parseaddr(raw or "")
    return {"name": _dh(name) or addr, "email": addr}


def _extract_text(msg) -> str:
    """Prefer text/plain; fall back to text/html decoded."""
    plain: Optional[str] = None
    html: Optional[str] = None
    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            disp = str(part.get("Content-Disposition") or "")
            if "attachment" in disp:
                continue
            if ctype == "text/plain" and plain is None:
                plain = _payload(part)
            elif ctype == "text/html" and html is None:
                html = _payload(part)
    else:
        if msg.get_content_type() == "text/html":
            html = _payload(msg)
        else:
            plain = _payload(msg)
    return (plain or html or "").strip()


def _payload(part) -> str:
    try:
        raw = part.get_payload(decode=True)
        if raw is None:
            return ""
        charset = part.get_content_charset() or "utf-8"
        return raw.decode(charset, "replace")
    except Exception:
        return ""


def _header_summary(uid: bytes, info: bytes, hdr_bytes: bytes) -> Dict[str, Any]:
    try:
        flags = imaplib.ParseFlags(info)
    except Exception:
        flags = ()
    unread = b"\\Seen" not in flags
    msg = email_lib.message_from_bytes(hdr_bytes)
    return {
        "id": uid.decode() if isinstance(uid, bytes) else str(uid),
        "thread_id": "",
        "from": _split_addr(_dh(msg.get("From", ""))),
        "subject": _dh(msg.get("Subject", "")),
        "date": msg.get("Date", ""),
        "snippet": "",
        "unread": unread,
        "message_id_header": (msg.get("Message-ID", "") or "").strip(),
    }


def list_messages(query: str = "is:unread", max_results: int = 20) -> List[Dict[str, Any]]:
    """List INBOX messages (metadata), newest first. 'is:unread' → UNSEEN, else ALL."""
    M = _imap(readonly=True)
    try:
        criterion = "UNSEEN" if "unread" in (query or "").lower() else "ALL"
        typ, data = M.uid("search", None, criterion)
        uids = data[0].split() if data and data and data[0] else []
        uids = uids[-max(1, min(max_results, 50)):]
        uids = list(reversed(uids))  # newest first
        out: List[Dict[str, Any]] = []
        for uid in uids:
            typ, d = M.uid(
                "fetch", uid,
                "(FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])",
            )
            if not d or not isinstance(d[0], tuple):
                continue
            info, hdr = d[0][0], d[0][1]
            out.append(_header_summary(uid, info, hdr))
        return out
    except GmailError:
        raise
    except Exception as exc:
        raise GmailError(f"Failed to list messages: {exc}") from exc
    finally:
        _logout(M)


def get_message(msg_id: str) -> Dict[str, Any]:
    """Fetch one full message including its text body (does not mark read)."""
    M = _imap(readonly=True)
    try:
        typ, d = M.uid("fetch", msg_id, "(FLAGS BODY.PEEK[])")
        if not d or not isinstance(d[0], tuple):
            raise GmailError("Message not found")
        info, raw = d[0][0], d[0][1]
        try:
            flags = imaplib.ParseFlags(info)
        except Exception:
            flags = ()
        msg = email_lib.message_from_bytes(raw)
        return {
            "id": str(msg_id),
            "thread_id": "",
            "from": _split_addr(_dh(msg.get("From", ""))),
            "to": _dh(msg.get("To", "")),
            "subject": _dh(msg.get("Subject", "")),
            "date": msg.get("Date", ""),
            "message_id_header": (msg.get("Message-ID", "") or "").strip(),
            "snippet": _extract_text(msg)[:160],
            "body": _extract_text(msg),
            "unread": b"\\Seen" not in flags,
        }
    except GmailError:
        raise
    except Exception as exc:
        raise GmailError(f"Failed to fetch message: {exc}") from exc
    finally:
        _logout(M)


def _build_mime(c: Dict[str, Any], to: str, subject: str, body: str, in_reply_to: str = ""):
    mime = MIMEText(body, "plain", "utf-8")
    mime["From"] = c["address"]
    mime["To"] = to
    mime["Subject"] = subject
    if in_reply_to:
        mime["In-Reply-To"] = in_reply_to
        mime["References"] = in_reply_to
    return mime


def send_message(
    to: str,
    subject: str,
    body: str,
    thread_id: Optional[str] = None,  # unused for SMTP; kept for signature parity
    in_reply_to: str = "",
) -> Dict[str, Any]:
    """Send an email via SMTP. [in_reply_to] (a Message-ID) threads the reply."""
    c = _require_config()
    if not (to or "").strip():
        raise GmailError("Recipient (to) is required")
    try:
        mime = _build_mime(c, to, subject, body, in_reply_to)
        server = smtplib.SMTP(c["smtp_host"], c["smtp_port"], timeout=30)
        try:
            server.starttls()
            server.login(c["address"], c["password"])
            server.sendmail(c["address"], [to], mime.as_string())
        finally:
            try:
                server.quit()
            except Exception:
                pass
        return {"status": "sent", "to": to}
    except GmailError:
        raise
    except Exception as exc:
        raise GmailError(f"Failed to send: {exc}") from exc


def create_draft(
    to: str,
    subject: str,
    body: str,
    thread_id: Optional[str] = None,
    in_reply_to: str = "",
) -> Dict[str, Any]:
    """Save a draft to the Gmail Drafts mailbox via IMAP APPEND."""
    c = _require_config()
    M = _imap(readonly=False)
    try:
        mime = _build_mime(c, to, subject, body, in_reply_to)
        M.append(
            DRAFTS_MAILBOX,
            "(\\Draft)",
            imaplib.Time2Internaldate(time.time()),
            mime.as_bytes(),
        )
        return {"status": "draft"}
    except GmailError:
        raise
    except Exception as exc:
        raise GmailError(f"Failed to create draft: {exc}") from exc
    finally:
        _logout(M)


def mark_read(msg_id: str) -> Dict[str, Any]:
    """Mark a message read (set the \\Seen flag)."""
    M = _imap(readonly=False)
    try:
        M.uid("store", msg_id, "+FLAGS", "(\\Seen)")
        return {"id": msg_id, "status": "read"}
    except GmailError:
        raise
    except Exception as exc:
        raise GmailError(f"Failed to mark read: {exc}") from exc
    finally:
        _logout(M)


def modify_labels(msg_id: str, add=None, remove=None) -> Dict[str, Any]:
    """Compatibility shim: IMAP has no Gmail labels. Only unread toggling maps —
    ``remove=['UNREAD']`` marks read."""
    if remove and "UNREAD" in remove:
        return mark_read(msg_id)
    return {"id": msg_id, "status": "noop"}
