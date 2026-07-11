"""Google Calendar tool — one compressed action tool for the agent.

Exposes calendar read/write to the model through a single ``google_calendar``
tool with an ``action`` enum, mirroring the ``cronjob`` tool's shape. Powers
natural-language scheduling ("lunch with Sam tomorrow 1pm" → ``quick_add``),
daily briefings (``list_events`` over today), and smart reminders (a cron job
reads upcoming events and pushes them via ntfy).

Auth + token lifecycle live in ``tools.google_calendar_auth``; this module is
just the tool surface + request/response shaping.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Optional

from tools.google_calendar_auth import (
    authorize,
    build_service,
    has_client_config,
    is_authorized,
)
from tools.registry import registry, tool_error

logger = logging.getLogger(__name__)

DEFAULT_CALENDAR = "primary"
DEFAULT_MAX_RESULTS = 20


GOOGLE_CALENDAR_SCHEMA = {
    "name": "google_calendar",
    "description": """Read and manage the user's Google Calendar.

Actions:
- action='status'        — check whether Calendar is authorized/configured.
- action='authorize'     — run the one-time OAuth consent (opens a browser on the host).
- action='list_calendars'— list the user's calendars and their ids.
- action='list_events'   — list events. Use time_min/time_max (ISO 8601) to bound a window; defaults to now → +7 days. Great for daily briefings.
- action='create_event'  — create an event from explicit fields (summary + start + end).
- action='quick_add'     — create an event from a natural-language phrase (e.g. 'Lunch with Sam tomorrow 1pm'). Best for conversational scheduling.
- action='update_event'  — update fields of an existing event (needs event_id).
- action='delete_event'  — delete an event (needs event_id).

Times are ISO 8601. For a timed event pass start/end like '2026-07-12T13:00:00'
plus a 'timezone' (IANA, e.g. 'America/New_York'); for an all-day event pass a
date like '2026-07-12'. Always list_events first to get an event_id before
update/delete — never guess ids.""",
    "parameters": {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": [
                    "status",
                    "authorize",
                    "list_calendars",
                    "list_events",
                    "create_event",
                    "quick_add",
                    "update_event",
                    "delete_event",
                ],
                "description": "The calendar operation to perform.",
            },
            "calendar_id": {
                "type": "string",
                "description": "Target calendar id. Defaults to 'primary'.",
            },
            "event_id": {
                "type": "string",
                "description": "Event id — REQUIRED for update_event and delete_event.",
            },
            "summary": {
                "type": "string",
                "description": "Event title (create_event; optional on update_event).",
            },
            "start": {
                "type": "string",
                "description": "Start time. ISO datetime '2026-07-12T13:00:00' (timed) or date '2026-07-12' (all-day).",
            },
            "end": {
                "type": "string",
                "description": "End time, same format as start. If omitted for a timed event, defaults to start + 1 hour.",
            },
            "timezone": {
                "type": "string",
                "description": "IANA timezone for timed events (e.g. 'America/New_York'). Defaults to the calendar's timezone.",
            },
            "description": {
                "type": "string",
                "description": "Event description / notes.",
            },
            "location": {
                "type": "string",
                "description": "Event location.",
            },
            "attendees": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Attendee email addresses.",
            },
            "text": {
                "type": "string",
                "description": "For quick_add: the natural-language phrase describing the event.",
            },
            "time_min": {
                "type": "string",
                "description": "For list_events: ISO lower bound. Defaults to now.",
            },
            "time_max": {
                "type": "string",
                "description": "For list_events: ISO upper bound. Defaults to now + 7 days.",
            },
            "query": {
                "type": "string",
                "description": "For list_events: free-text search filter.",
            },
            "max_results": {
                "type": "integer",
                "description": f"For list_events: cap on results (default {DEFAULT_MAX_RESULTS}).",
            },
        },
        "required": ["action"],
    },
}


def _now_iso() -> str:
    # Local wall-clock is unavailable in scripts elsewhere, but the tool runs in
    # the live agent process where the system clock is fine.
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


def _plus_days_iso(days: int) -> str:
    from datetime import datetime, timedelta, timezone

    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()


def _time_field(value: str, timezone_name: Optional[str]) -> dict:
    """Build a Calendar API start/end object from an ISO string.

    A bare date ('2026-07-12') → all-day ({"date": ...}); anything with a 'T'
    → timed ({"dateTime": ..., "timeZone": ...}).
    """
    value = value.strip()
    if "T" not in value and len(value) == 10:
        return {"date": value}
    field: dict[str, Any] = {"dateTime": value}
    if timezone_name:
        field["timeZone"] = timezone_name
    return field


def _default_end(start: str) -> str:
    """Return start + 1h for timed events; for all-day, the same date."""
    if "T" not in start:
        return start
    try:
        from datetime import datetime, timedelta

        dt = datetime.fromisoformat(start)
        return (dt + timedelta(hours=1)).isoformat()
    except Exception:
        return start


def _summarize_event(ev: dict) -> dict:
    start = ev.get("start", {})
    end = ev.get("end", {})
    return {
        "id": ev.get("id"),
        "summary": ev.get("summary", "(no title)"),
        "start": start.get("dateTime") or start.get("date"),
        "end": end.get("dateTime") or end.get("date"),
        "location": ev.get("location"),
        "attendees": [a.get("email") for a in ev.get("attendees", []) if a.get("email")],
        "htmlLink": ev.get("htmlLink"),
    }


def _handle(args: dict) -> str:
    action = (args.get("action") or "").strip()
    if not action:
        return tool_error("'action' is required")

    # Meta actions that don't need a live service.
    if action == "status":
        return json.dumps({
            "client_configured": has_client_config(),
            "authorized": is_authorized(),
            "hint": (
                "Ready." if is_authorized()
                else "Run action='authorize' (or `python -m tools.google_calendar_auth`)."
            ),
        })

    if action == "authorize":
        return json.dumps(authorize())

    service = build_service()
    if service is None:
        if not has_client_config():
            return tool_error(
                "Google Calendar not configured. Set GOOGLE_CALENDAR_CLIENT_ID/"
                "GOOGLE_CALENDAR_CLIENT_SECRET or place client_secret.json under "
                "~/.hermes/google_calendar/, then run action='authorize'."
            )
        return tool_error(
            "Google Calendar not authorized yet. Run action='authorize' first."
        )

    calendar_id = (args.get("calendar_id") or DEFAULT_CALENDAR).strip()

    try:
        if action == "list_calendars":
            items = service.calendarList().list().execute().get("items", [])
            calendars = [
                {
                    "id": c.get("id"),
                    "summary": c.get("summary"),
                    "primary": c.get("primary", False),
                    "timeZone": c.get("timeZone"),
                }
                for c in items
            ]
            return json.dumps({"calendars": calendars})

        if action == "list_events":
            time_min = (args.get("time_min") or _now_iso()).strip()
            time_max = (args.get("time_max") or _plus_days_iso(7)).strip()
            max_results = int(args.get("max_results") or DEFAULT_MAX_RESULTS)
            request = service.events().list(
                calendarId=calendar_id,
                timeMin=time_min,
                timeMax=time_max,
                singleEvents=True,
                orderBy="startTime",
                maxResults=max(1, min(max_results, 250)),
                q=(args.get("query") or None),
            )
            events = request.execute().get("items", [])
            return json.dumps({
                "count": len(events),
                "events": [_summarize_event(e) for e in events],
            })

        if action == "quick_add":
            text = (args.get("text") or "").strip()
            if not text:
                return tool_error("'text' is required for quick_add")
            created = service.events().quickAdd(
                calendarId=calendar_id, text=text
            ).execute()
            return json.dumps({"created": _summarize_event(created)})

        if action == "create_event":
            summary = (args.get("summary") or "").strip()
            start = (args.get("start") or "").strip()
            if not summary or not start:
                return tool_error(
                    "'summary' and 'start' are required for create_event"
                )
            end = (args.get("end") or "").strip() or _default_end(start)
            tz = args.get("timezone")
            body: dict[str, Any] = {
                "summary": summary,
                "start": _time_field(start, tz),
                "end": _time_field(end, tz),
            }
            if args.get("description"):
                body["description"] = args["description"]
            if args.get("location"):
                body["location"] = args["location"]
            attendees = args.get("attendees") or []
            if attendees:
                body["attendees"] = [{"email": e} for e in attendees]
            created = service.events().insert(
                calendarId=calendar_id, body=body
            ).execute()
            return json.dumps({"created": _summarize_event(created)})

        if action == "update_event":
            event_id = (args.get("event_id") or "").strip()
            if not event_id:
                return tool_error("'event_id' is required for update_event")
            # Patch only the provided fields to avoid clobbering the rest.
            patch: dict[str, Any] = {}
            if args.get("summary"):
                patch["summary"] = args["summary"]
            if args.get("description"):
                patch["description"] = args["description"]
            if args.get("location"):
                patch["location"] = args["location"]
            tz = args.get("timezone")
            if args.get("start"):
                patch["start"] = _time_field(args["start"].strip(), tz)
            if args.get("end"):
                patch["end"] = _time_field(args["end"].strip(), tz)
            if args.get("attendees"):
                patch["attendees"] = [{"email": e} for e in args["attendees"]]
            if not patch:
                return tool_error("No fields to update were provided")
            updated = service.events().patch(
                calendarId=calendar_id, eventId=event_id, body=patch
            ).execute()
            return json.dumps({"updated": _summarize_event(updated)})

        if action == "delete_event":
            event_id = (args.get("event_id") or "").strip()
            if not event_id:
                return tool_error("'event_id' is required for delete_event")
            service.events().delete(
                calendarId=calendar_id, eventId=event_id
            ).execute()
            return json.dumps({"deleted": event_id})

        return tool_error(f"Unknown action: {action}")

    except Exception as exc:
        logger.exception("google_calendar action '%s' failed", action)
        return tool_error(f"Google Calendar {action} failed: {exc}")


def check_google_calendar_requirements() -> bool:
    """Surface the tool only when Calendar is usable.

    Visible when the user has either authorized already or configured OAuth
    client credentials (so the model can drive the 'authorize' action). Hidden
    entirely on hosts with no Calendar setup — keeps the schema narrow.
    """
    return is_authorized() or has_client_config()


registry.register(
    name="google_calendar",
    toolset="google_calendar",
    schema=GOOGLE_CALENDAR_SCHEMA,
    handler=lambda args, **kw: _handle(args),
    check_fn=check_google_calendar_requirements,
    emoji="📅",
)
