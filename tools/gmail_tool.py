"""Gmail tool — one compressed action tool for the agent.

Exposes read/list/send/draft/reply/mark-read over the user's Gmail through a
single ``gmail`` tool with an ``action`` enum, mirroring the ``google_calendar``
tool. Powers the mobile AI-email flow and the new-mail cron notifier.

Auth lives in ``tools.gmail_auth``; the Gmail API operations live in
``tools.gmail_core`` (shared with the api_server ``/api/email/*`` endpoints).
"""

from __future__ import annotations

import json
import logging
from typing import Any

from tools import gmail_core
from tools.registry import registry, tool_error

logger = logging.getLogger(__name__)

DEFAULT_QUERY = "is:unread"
DEFAULT_MAX = 15


GMAIL_SCHEMA = {
    "name": "gmail",
    "description": """Read and manage the user's Gmail.

Actions:
- action='status'    — check whether email (IMAP/SMTP) is configured.
- action='list'      — list unread/recent messages ('query' 'is:unread' → unread, else recent). Returns id, from, subject, unread. Use for briefings / "any new email?".
- action='get'       — fetch one full message body (needs 'id'). List first to get ids — never guess.
- action='send'      — send a new email (needs 'to', 'subject', 'body').
- action='reply'     — reply within a thread (needs 'id' of the message being replied to, plus 'body'). Auto-fills recipient/subject/threading.
- action='draft'     — create a draft without sending (same fields as send).
- action='mark_read' — mark a message read (needs 'id').

Gmail search syntax works in 'query' (e.g. 'is:unread', 'from:alice newer_than:2d', 'label:important'). Always confirm with the user before send/reply.""",
    "parameters": {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["status", "list", "get", "send", "reply", "draft", "mark_read"],
                "description": "The mail operation to perform.",
            },
            "query": {"type": "string", "description": "Gmail search query for 'list' (default 'is:unread')."},
            "max_results": {"type": "integer", "description": "Max messages for 'list' (default 15, cap 50)."},
            "id": {"type": "string", "description": "Message id — required for get/reply/mark_read."},
            "to": {"type": "string", "description": "Recipient email — required for send."},
            "subject": {"type": "string", "description": "Subject — for send/draft."},
            "body": {"type": "string", "description": "Message body (plain text) — for send/reply/draft."},
        },
        "required": ["action"],
    },
}


def _handle(args: dict) -> str:
    action = (args.get("action") or "").strip()

    if action == "status":
        return json.dumps({"configured": gmail_core.is_configured()})

    try:
        if action == "list":
            msgs = gmail_core.list_messages(
                query=(args.get("query") or DEFAULT_QUERY),
                max_results=int(args.get("max_results") or DEFAULT_MAX),
            )
            return json.dumps({"messages": msgs, "count": len(msgs)})

        if action == "get":
            mid = (args.get("id") or "").strip()
            if not mid:
                return tool_error("'id' is required for get")
            return json.dumps({"message": gmail_core.get_message(mid)})

        if action == "send":
            return json.dumps(gmail_core.send_message(
                to=(args.get("to") or "").strip(),
                subject=(args.get("subject") or "").strip(),
                body=(args.get("body") or ""),
            ))

        if action == "reply":
            mid = (args.get("id") or "").strip()
            if not mid:
                return tool_error("'id' of the message being replied to is required for reply")
            original = gmail_core.get_message(mid)
            subj = original.get("subject", "")
            if subj and not subj.lower().startswith("re:"):
                subj = f"Re: {subj}"
            return json.dumps(gmail_core.send_message(
                to=original["from"]["email"],
                subject=subj,
                body=(args.get("body") or ""),
                thread_id=original.get("thread_id"),
                in_reply_to=original.get("message_id_header", ""),
            ))

        if action == "draft":
            return json.dumps(gmail_core.create_draft(
                to=(args.get("to") or "").strip(),
                subject=(args.get("subject") or "").strip(),
                body=(args.get("body") or ""),
            ))

        if action == "mark_read":
            mid = (args.get("id") or "").strip()
            if not mid:
                return tool_error("'id' is required for mark_read")
            return json.dumps(gmail_core.mark_read(mid))

        return tool_error(f"Unknown action: {action}")

    except gmail_core.GmailError as exc:
        return tool_error(str(exc))
    except Exception as exc:
        logger.exception("gmail action '%s' failed", action)
        return tool_error(f"Gmail {action} failed: {exc}")


def check_gmail_requirements() -> bool:
    """Surface the tool only when email (IMAP/SMTP) credentials are configured."""
    return gmail_core.is_configured()


registry.register(
    name="gmail",
    toolset="gmail",
    schema=GMAIL_SCHEMA,
    handler=lambda args, **kw: _handle(args),
    check_fn=check_gmail_requirements,
    emoji="📧",
)
