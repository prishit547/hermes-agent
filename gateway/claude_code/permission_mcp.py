"""Permission-prompt MCP server for Atlantic Dev per-action approvals.

Claude Code is launched (in ``approve`` mode) with
``--permission-prompt-tool mcp__atlantic__approval_request`` and an inline
``--mcp-config`` that runs THIS script over stdio. Whenever the CLI wants to use
a gated tool (Edit / Write / Bash / …), it calls ``approval_request`` with
``{tool_name, input, tool_use_id}``; we forward that to the gateway's
[ClaudeCodeManager] over a Unix-domain socket and block until the phone answers,
then return the CLI's required decision as a SINGLE text block:

    {"behavior": "allow", "updatedInput": {...}}   |   {"behavior": "deny", "message": "..."}

Notes learned by probing the CLI (v2.1.211):
 - The low-level ``mcp.server.Server`` is required — FastMCP attaches
   ``structuredContent`` alongside the text block and the CLI rejects it with
   "Expected a single text block".
 - Read is auto-allowed and never routed here; only consequential tools are.
 - The CLI tolerates human-speed responses (verified to 15s+), so blocking on a
   phone tap is fine.

Self-contained: only stdlib + the ``mcp`` SDK, so it runs from any cwd under the
gateway's interpreter regardless of PYTHONPATH.
"""

from __future__ import annotations

import asyncio
import json
import os

from mcp.server import Server
from mcp.server.stdio import stdio_server
import mcp.types as types

_SOCK = os.environ.get("HERMES_CC_SOCK", "")
_SESSION = os.environ.get("HERMES_CC_SESSION", "")
_TOKEN = os.environ.get("HERMES_CC_TOKEN", "")

server = Server("atlantic")


@server.list_tools()
async def _list_tools():
    return [
        types.Tool(
            name="approval_request",
            description="Request phone approval before Claude Code uses a tool.",
            inputSchema={
                "type": "object",
                "properties": {
                    "tool_name": {"type": "string"},
                    "input": {"type": "object"},
                    "tool_use_id": {"type": "string"},
                },
                "required": ["tool_name", "input"],
            },
        )
    ]


@server.call_tool()
async def _call_tool(name, arguments):
    decision = await _ask_gateway(arguments or {})
    return [types.TextContent(type="text", text=json.dumps(decision))]


async def _ask_gateway(arguments: dict) -> dict:
    if not _SOCK:
        return {"behavior": "deny", "message": "approval bridge not configured"}
    payload = {
        "token": _TOKEN,
        "session_id": _SESSION,
        "tool_name": arguments.get("tool_name", ""),
        "input": arguments.get("input", {}),
        "tool_use_id": arguments.get("tool_use_id", ""),
    }
    try:
        reader, writer = await asyncio.open_unix_connection(_SOCK)
        writer.write((json.dumps(payload) + "\n").encode("utf-8"))
        await writer.drain()
        line = await reader.readline()
        try:
            writer.close()
        except Exception:
            pass
        if not line:
            return {"behavior": "deny", "message": "approval bridge closed"}
        decision = json.loads(line.decode("utf-8"))
        if isinstance(decision, dict) and decision.get("behavior") in ("allow", "deny"):
            return decision
        return {"behavior": "deny", "message": "malformed approval decision"}
    except Exception as exc:  # noqa: BLE001 — fail closed
        return {"behavior": "deny", "message": f"approval bridge error: {exc}"}


async def _main():
    async with stdio_server() as (r, w):
        await server.run(r, w, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(_main())
