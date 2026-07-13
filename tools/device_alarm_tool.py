#!/usr/bin/env python3
"""Device Alarm tool for the Hermes agent.

Allows the agent to schedule on-device alarms by pushing a control command
via the user's configured ntfy channel.
"""

import json
import os
import urllib.request
import urllib.error
from pathlib import Path

from hermes_constants import get_hermes_home
from tools.registry import registry, tool_error


def _load_env_vars():
    """Manually load ~/.hermes/.env variables into os.environ if needed."""
    env_path = Path(get_hermes_home()) / ".env"
    if env_path.exists():
        try:
            for line in env_path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    k, v = k.strip(), v.strip()
                    if k not in os.environ:
                        os.environ[k] = v
        except Exception:
            pass


def device_alarm_tool(time: str, title: str) -> str:
    """Publish a create_alarm action to the ntfy channel."""
    _load_env_vars()

    topic = os.getenv("NTFY_TOPIC") or os.getenv("NTFY_HOME_CHANNEL")
    if not topic:
        return tool_error("No NTFY_TOPIC or NTFY_HOME_CHANNEL configured in ~/.hermes/.env on the server.")

    server = os.getenv("NTFY_SERVER_URL", "https://ntfy.sh").rstrip("/")
    url = f"{server}/{topic}"

    # Build the action JSON payload
    payload = {
        "action": "create_alarm",
        "time": time,
        "title": title or "Alarm",
    }
    body_str = json.dumps(payload)

    # Make the HTTP POST request to ntfy
    req = urllib.request.Request(url, data=body_str.encode("utf-8"), method="POST")
    req.add_header("Content-Type", "text/plain; charset=utf-8")
    req.add_header("Title", "Create Device Alarm")
    req.add_header("Priority", "5")  # Max priority on ntfy
    req.add_header("Tags", "alarm")

    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            if resp.status in (200, 201):
                return json.dumps({
                    "status": "success",
                    "message": "Alarm successfully pushed to device",
                    "time": time,
                    "title": title
                }, ensure_ascii=False)
            return tool_error(f"Failed to post to ntfy. HTTP status: {resp.status}")
    except urllib.error.URLError as e:
        return tool_error(f"Network error posting to ntfy: {e}")
    except Exception as e:
        return tool_error(f"Unexpected error: {e}")


DEVICE_ALARM_SCHEMA = {
    "name": "device_alarm",
    "description": (
        "Schedule an alarm or reminder on the user's mobile device (phone) using natural language. "
        "Use this tool when the user asks you to set an alarm, alert, or reminder for a specific time. "
        "The time parameter MUST be a timezone-aware ISO 8601 string (e.g. 2026-07-13T07:30:00+05:30)."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "time": {
                "type": "string",
                "description": "The exact date and time when the alarm should go off, in ISO 8601 format (e.g. 2026-07-14T07:30:00+05:30).",
            },
            "title": {
                "type": "string",
                "description": "The label/title for the alarm (e.g. 'Wake up' or 'Meeting reminder').",
            },
        },
        "required": ["time", "title"],
    },
}

registry.register(
    name="device_alarm",
    toolset="alarm",
    schema=DEVICE_ALARM_SCHEMA,
    handler=lambda args, **kw: device_alarm_tool(
        time=args.get("time", ""),
        title=args.get("title", ""),
    ),
    emoji="⏰",
)
