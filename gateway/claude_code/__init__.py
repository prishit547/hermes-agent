"""Atlantic Dev — drive the locally-installed ``claude`` CLI from the phone.

A gateway-owned service (not an agent tool) that launches the real Claude Code
CLI in headless ``--output-format stream-json`` mode against whitelisted local
repos, normalises its event stream, and exposes it over the api_server's
Bearer-authed ``/api/code/*`` routes so the mobile app can hold a live coding
session on a project.

Phase 1: safe-by-default sessions (``default``/``plan`` mode reads & proposes;
``acceptEdits`` mode writes to the working tree). Nothing leaves the machine
until an explicit, phone-approved commit/push. Per-action approval via a
``--permission-prompt-tool`` MCP bridge is a later phase.
"""

from __future__ import annotations

from gateway.claude_code.manager import ClaudeCodeManager, get_manager

__all__ = ["ClaudeCodeManager", "get_manager"]
