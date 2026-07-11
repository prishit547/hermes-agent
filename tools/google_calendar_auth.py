"""Google Calendar OAuth + credential management for the calendar tool.

Personal Google Calendar access requires **user-consent OAuth** (the installed-
app / loopback flow) — a service account cannot read a personal calendar
without Workspace domain-wide delegation. This module owns that flow and the
resulting token lifecycle:

- One-time consent via ``authorize()`` (opens a browser, catches the loopback
  redirect, exchanges the code, persists a refresh token).
- ``get_credentials()`` loads the stored token and silently refreshes it when
  expired, so the tool never re-prompts once authorized.

Client credentials (the OAuth *app* identity) come from either:
1. ``GOOGLE_CALENDAR_CLIENT_ID`` + ``GOOGLE_CALENDAR_CLIENT_SECRET`` env vars, or
2. a ``client_secret.json`` downloaded from Google Cloud Console, placed at
   ``~/.hermes/google_calendar/client_secret.json``.

The heavy ``google-*`` packages are imported lazily so hosts that never touch
Calendar don't pay the import cost.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any, Optional

from hermes_constants import get_hermes_home

logger = logging.getLogger(__name__)

# Read/write access to events on the user's calendars. Kept to the single
# ``calendar`` scope (not ``calendar.events`` only) so list_calendars works too.
SCOPES = ["https://www.googleapis.com/auth/calendar"]


def _try_lazy_install() -> bool:
    """Best-effort lazy install of the google-* packages. Returns True on success."""
    try:
        import importlib.util as _ilu

        from tools.lazy_deps import ensure

        ensure("google.calendar", prompt=False)
        return bool(
            _ilu.find_spec("googleapiclient")
            and _ilu.find_spec("google_auth_oauthlib")
        )
    except Exception as exc:
        logger.debug("Lazy install of google.calendar failed: %s", exc)
        return False


def _config_dir() -> Path:
    return get_hermes_home() / "google_calendar"


def _token_path() -> Path:
    return _config_dir() / "token.json"


def _client_secret_path() -> Path:
    return _config_dir() / "client_secret.json"


def _load_client_config() -> Optional[dict]:
    """Return an InstalledAppFlow client config dict, or None if unconfigured.

    Env vars win over the on-disk ``client_secret.json`` so a headless/server
    setup can supply credentials without a file.
    """
    client_id = os.getenv("GOOGLE_CALENDAR_CLIENT_ID", "").strip()
    client_secret = os.getenv("GOOGLE_CALENDAR_CLIENT_SECRET", "").strip()
    if client_id and client_secret:
        return {
            "installed": {
                "client_id": client_id,
                "client_secret": client_secret,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
                "redirect_uris": ["http://localhost"],
            }
        }

    secret_file = _client_secret_path()
    if secret_file.exists():
        try:
            return json.loads(secret_file.read_text(encoding="utf-8"))
        except Exception as exc:
            logger.warning("Invalid client_secret.json: %s", exc)
            return None
    return None


def has_client_config() -> bool:
    """True when OAuth *app* credentials are available (env or file)."""
    return _load_client_config() is not None


def is_authorized() -> bool:
    """True when a stored user token exists (does not verify it still refreshes)."""
    return _token_path().exists()


def get_credentials() -> Optional[Any]:
    """Return valid Google ``Credentials``, refreshing if needed, else None.

    Returns None (rather than raising) when the user has not authorized yet or
    the token is unrecoverable — callers surface a friendly "run authorize"
    message instead of a stack trace.
    """
    token_file = _token_path()
    if not token_file.exists():
        return None

    try:
        from google.oauth2.credentials import Credentials
        from google.auth.transport.requests import Request
    except ImportError as exc:
        logger.warning("google-auth not installed: %s", exc)
        return None

    try:
        creds = Credentials.from_authorized_user_file(str(token_file), SCOPES)
    except Exception as exc:
        logger.warning("Could not load Google token: %s", exc)
        return None

    if creds and creds.valid:
        return creds

    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            _save_token(creds)
            return creds
        except Exception as exc:
            logger.warning("Google token refresh failed: %s", exc)
            return None

    return None


def _save_token(creds: Any) -> None:
    config_dir = _config_dir()
    config_dir.mkdir(parents=True, exist_ok=True)
    token_file = _token_path()
    token_file.write_text(creds.to_json(), encoding="utf-8")
    # Token holds a refresh token — restrict to owner only.
    try:
        os.chmod(token_file, 0o600)
    except OSError:
        pass


def authorize(*, port: int = 0, open_browser: bool = True) -> dict:
    """Run the one-time OAuth consent flow and persist the token.

    Returns ``{"success": bool, "error"|"message": str}``. Blocks on a local
    loopback server until the user completes consent in their browser.
    """
    client_config = _load_client_config()
    if client_config is None:
        return {
            "success": False,
            "error": (
                "No Google OAuth client configured. Set "
                "GOOGLE_CALENDAR_CLIENT_ID/GOOGLE_CALENDAR_CLIENT_SECRET, or "
                f"place client_secret.json at {_client_secret_path()}. Create "
                "credentials at https://console.cloud.google.com/apis/credentials "
                "(OAuth client ID → Desktop app), and enable the Google "
                "Calendar API for the project."
            ),
        }

    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError:
        if not _try_lazy_install():
            return {
                "success": False,
                "error": (
                    "google-auth-oauthlib not installed. Install with: "
                    "uv pip install google-auth-oauthlib google-api-python-client"
                ),
            }
        from google_auth_oauthlib.flow import InstalledAppFlow

    try:
        flow = InstalledAppFlow.from_client_config(client_config, SCOPES)
        creds = flow.run_local_server(port=port, open_browser=open_browser)
        _save_token(creds)
        return {"success": True, "message": "Google Calendar authorized."}
    except Exception as exc:
        logger.exception("Google Calendar OAuth flow failed")
        return {"success": False, "error": f"OAuth flow failed: {exc}"}


def build_service() -> Optional[Any]:
    """Build an authorized Calendar API service client, or None if unauthorized."""
    creds = get_credentials()
    if creds is None:
        return None
    try:
        from googleapiclient.discovery import build
    except ImportError as exc:
        if not _try_lazy_install():
            logger.warning("google-api-python-client not installed: %s", exc)
            return None
        from googleapiclient.discovery import build
    # cache_discovery=False avoids a noisy warning + file cache under some envs.
    return build("calendar", "v3", credentials=creds, cache_discovery=False)


def main() -> None:
    """Allow ``python -m tools.google_calendar_auth`` to run consent from a shell."""
    logging.basicConfig(level=logging.INFO)
    result = authorize()
    if result.get("success"):
        print("✓", result.get("message"))
    else:
        print("✗", result.get("error"))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
