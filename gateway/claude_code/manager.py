"""ClaudeCodeManager — persistent Claude Code sessions over the local CLI.

One "session" maps to one Claude Code conversation (identified by the CLI's own
``session_id``) bound to one whitelisted project directory. Each user turn spawns

    claude --print --output-format stream-json --verbose \
           --permission-mode <mode> [--resume <claude_session_id>] [--model <m>] \
           <prompt>

with ``cwd`` set to the repo. We read the CLI's newline-delimited JSON events,
capture the ``session_id`` from the ``init`` event on the first turn, persist it,
and ``--resume`` it on subsequent turns. Resume keeps full conversation context
and survives gateway restarts (state lives on disk in ~/.claude), so we never
need to babysit a long-lived child process.

Safety: the project allow-list is the trust boundary — the phone can only touch
directories the user explicitly listed in ``claude_code.projects``. Prompts are
passed as argv (no shell), so there is no shell-injection surface.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import secrets
import shutil
import sys
import time
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, AsyncIterator, Dict, List, Optional, Tuple

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover — Python 3.9+ ships zoneinfo
    ZoneInfo = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)

# CLI stream-json lines can be large (thinking-block signatures, big tool
# results, the terminal ``result`` event). The default asyncio StreamReader
# limit is 64 KiB and readline() raises LimitOverrunError past it — bump it.
_STREAM_LIMIT = 16 * 1024 * 1024

# Modes we accept from the client. ``bypassPermissions`` is deliberately NOT
# offered: it disables all guardrails and is never appropriate for a
# phone-driven session.
#   plan/default — read & investigate, edits auto-denied (safe)
#   approve       — Claude may edit/run, but each gated action needs a phone tap
#                   (routed through the permission MCP bridge)
#   acceptEdits   — edits auto-apply to the working tree (power user)
_ALLOWED_MODES = {"plan", "default", "approve", "acceptEdits"}
_DEFAULT_MODE = "default"

# How long a single permission request waits for the phone before failing closed.
_PERM_TIMEOUT = 600.0
_PERM_TOOL = "mcp__atlantic__approval_request"

_MAX_SESSIONS = 50
_MAX_RESULT_PREVIEW = 4000

# Human labels for the CLI's ``rateLimitType`` values (falls back to a
# title-cased version of the raw string for anything not listed here).
_RATE_LIMIT_LABELS = {
    "five_hour": "5-hour",
    "seven_day": "weekly",
    "weekly": "weekly",
}

# Default interval between free `/usage` checks (see _usage_poll_loop). Floor
# guards against a misconfigured near-zero value hammering the CLI.
_USAGE_POLL_SECONDS_DEFAULT = 900.0
_USAGE_POLL_SECONDS_MIN = 60.0


def _usage_poll_interval() -> float:
    raw = _load_config().get("usage_poll_seconds")
    try:
        val = float(raw)
    except (TypeError, ValueError):
        return _USAGE_POLL_SECONDS_DEFAULT
    return max(_USAGE_POLL_SECONDS_MIN, val)


# `/usage`'s reply is a fixed, non-LLM-generated template (verified: the CLI
# reports `"model":"<synthetic>"` and zero cost/tokens for it — it's a local
# account-metadata query, not a model call) so these patterns are stable
# across runs, though tied to the CLI's exact wording for this version.
_USAGE_SESSION_RE = re.compile(r"Current session:\s*(\d+)%\s*used([^\n]*)", re.IGNORECASE)
_USAGE_WEEK_RE = re.compile(r"Current week \(all models\):\s*(\d+)%\s*used([^\n]*)", re.IGNORECASE)
_USAGE_RESET_CLAUSE_RE = re.compile(
    r"resets\s+([A-Za-z]{3,9})\s+(\d{1,2})\s+at\s+(\d{1,2}):(\d{2})\s*(am|pm)\s*\(([^)]+)\)",
    re.IGNORECASE,
)
_MONTH_ABBR = {
    m: i + 1
    for i, m in enumerate(
        ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    )
}


def _parse_usage_reset_clause(text: str) -> Optional[float]:
    """Parse a `resets Jul 17 at 2:40pm (Asia/Calcutta)` clause into Unix seconds.

    No year is given, so we assume the current year and roll forward one year
    if that lands more than a few days in the past (handles the
    December → January boundary).
    """
    m = _USAGE_RESET_CLAUSE_RE.search(text)
    if not m:
        return None
    mon_str, day_str, hh_str, mm_str, ampm, tzname = m.groups()
    month = _MONTH_ABBR.get(mon_str.strip().lower()[:3])
    if month is None:
        return None
    tz = None
    if ZoneInfo is not None:
        try:
            tz = ZoneInfo(tzname.strip())
        except Exception:
            tz = None
    now = datetime.now(tz) if tz else datetime.utcnow()
    hour = int(hh_str) % 12
    if ampm.strip().lower() == "pm":
        hour += 12
    try:
        dt = datetime(now.year, month, int(day_str), hour, int(mm_str), tzinfo=tz)
    except ValueError:
        return None
    if (now - dt).total_seconds() > 3 * 86400:
        try:
            dt = dt.replace(year=now.year + 1)
        except ValueError:
            return None
    return dt.timestamp()


def _parse_usage_text(text: str) -> Dict[str, Any]:
    """Extract session/weekly usage percentages + reset times from `/usage`'s
    reply. Returns an empty dict if the expected lines aren't found (e.g. a
    CLI wording change, or an account type without these limits) — callers
    should treat that as "nothing to update," not an error."""
    out: Dict[str, Any] = {}
    m = _USAGE_SESSION_RE.search(text)
    if m:
        out["session_used_pct"] = int(m.group(1))
        out["session_resets_at"] = _parse_usage_reset_clause(m.group(2))
    m = _USAGE_WEEK_RE.search(text)
    if m:
        out["week_used_pct"] = int(m.group(1))
        out["week_resets_at"] = _parse_usage_reset_clause(m.group(2))
    return out


def _hermes_home() -> Path:
    try:
        from hermes_cli.config import get_hermes_home
        return Path(get_hermes_home())
    except Exception:
        return Path(os.path.expanduser("~/.hermes"))


def _atomic_write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + f".tmp-{os.getpid()}")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


# --------------------------------------------------------------------------
# Project allow-list
# --------------------------------------------------------------------------

@dataclass
class Project:
    name: str
    path: str

    def to_dict(self) -> Dict[str, Any]:
        return {"name": self.name, "path": self.path}


def _load_config() -> Dict[str, Any]:
    try:
        from hermes_cli.config import load_config, cfg_get
        cfg = load_config() or {}
        section = cfg_get(cfg, "claude_code", default=None)
        return section if isinstance(section, dict) else {}
    except Exception:
        logger.debug("[claude_code] config load failed", exc_info=True)
        return {}


def load_projects() -> List[Project]:
    """Read the whitelisted projects from ``claude_code.projects`` in config.yaml.

    Accepts either a list of ``{name, path}`` maps or a ``{name: path}`` mapping.
    Only existing directories are returned; ``~`` is expanded.
    """
    raw = _load_config().get("projects")
    items: List[Project] = []
    if isinstance(raw, dict):
        raw = [{"name": k, "path": v} for k, v in raw.items()]
    if isinstance(raw, list):
        for entry in raw:
            if not isinstance(entry, dict):
                continue
            name = str(entry.get("name") or "").strip()
            path = str(entry.get("path") or "").strip()
            if not name or not path:
                continue
            resolved = Path(os.path.expanduser(path)).resolve()
            if resolved.is_dir():
                items.append(Project(name=name, path=str(resolved)))
            else:
                logger.warning("[claude_code] project %r path does not exist: %s", name, resolved)
    return items


def resolve_project(name: str) -> Optional[Project]:
    for p in load_projects():
        if p.name == name:
            return p
    return None


def _claude_bin() -> str:
    configured = _load_config().get("claude_bin")
    if configured and Path(os.path.expanduser(configured)).exists():
        return os.path.expanduser(configured)
    found = shutil.which("claude")
    if found:
        return found
    fallback = os.path.expanduser("~/.local/bin/claude")
    return fallback if Path(fallback).exists() else "claude"


def _configured_model() -> Optional[str]:
    model = _load_config().get("model")
    return str(model) if model else None


# --------------------------------------------------------------------------
# Session state
# --------------------------------------------------------------------------

@dataclass
class Session:
    id: str
    project: str
    cwd: str
    permission_mode: str = _DEFAULT_MODE
    title: str = ""
    claude_session_id: Optional[str] = None
    status: str = "idle"  # idle | running | error
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    last_result: str = ""
    turns: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class UsageLedger:
    """Cumulative Claude Code usage, persisted across gateway restarts.

    ``last_check`` is the authoritative source, from periodically running the
    CLI's free ``/usage`` command (verified zero-cost — see
    ``_parse_usage_text``'s docstring): session/weekly percentages + exact
    reset times, and the sole trigger for reset notifications.

    ``last_rate_limit`` is a secondary, passive signal — the most recent
    ``rate_limit_event`` observed on a real turn (comes along for free, so we
    keep it) — used only for the live in-session "limit reached" indicator,
    since it updates immediately during an active turn rather than waiting for
    the next poll.

    ``reset_events`` is a capped history of detected reset transitions, for
    the app's usage timeline.
    """
    total_cost_usd: float = 0.0
    total_turns: int = 0
    per_project_cost_usd: Dict[str, float] = field(default_factory=dict)
    last_rate_limit: Optional[Dict[str, Any]] = None
    last_check: Optional[Dict[str, Any]] = None
    reset_events: List[Dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# Sentinel pushed onto a turn queue by the stdout reader when the CLI exits.
_TURN_DONE = object()


class _Turn:
    """Live state for one in-flight turn: the multiplexed event queue plus any
    permission requests awaiting a phone decision."""

    def __init__(self, perm_token: str) -> None:
        self.queue: "asyncio.Queue[Any]" = asyncio.Queue()
        # tool_use_id -> (future resolved with a decision dict, original input)
        self.pending: Dict[str, Tuple["asyncio.Future", Any]] = {}
        self.perm_token = perm_token


class ClaudeCodeManager:
    def __init__(self) -> None:
        self._store_path = _hermes_home() / "claude_code" / "sessions.json"
        self._usage_path = _hermes_home() / "claude_code" / "usage.json"
        self._sessions: Dict[str, Session] = {}
        self._running: Dict[str, asyncio.subprocess.Process] = {}
        self._turns: Dict[str, _Turn] = {}
        self._uds_path = str(_hermes_home() / "claude_code" / "perm.sock")
        self._uds_server: Optional[asyncio.AbstractServer] = None
        self._poll_task: Optional[asyncio.Task] = None
        self._lock = asyncio.Lock()
        self.usage = UsageLedger()
        self._load()
        self._load_usage()

    # -- persistence -------------------------------------------------------
    def _load(self) -> None:
        try:
            if self._store_path.exists():
                data = json.loads(self._store_path.read_text(encoding="utf-8"))
                for rec in (data.get("sessions") or {}).values():
                    try:
                        # Drop transient running state carried over a restart.
                        rec = dict(rec)
                        if rec.get("status") == "running":
                            rec["status"] = "idle"
                        s = Session(**{k: rec[k] for k in rec if k in Session.__dataclass_fields__})
                        self._sessions[s.id] = s
                    except Exception:
                        logger.debug("[claude_code] skipping bad session record", exc_info=True)
        except Exception:
            logger.warning("[claude_code] failed to load session store", exc_info=True)

    def _save(self) -> None:
        try:
            _atomic_write_json(self._store_path, {"sessions": {sid: s.to_dict() for sid, s in self._sessions.items()}})
        except Exception:
            logger.warning("[claude_code] failed to persist session store", exc_info=True)

    def _load_usage(self) -> None:
        try:
            if self._usage_path.exists():
                data = json.loads(self._usage_path.read_text(encoding="utf-8"))
                self.usage = UsageLedger(**{k: data[k] for k in data if k in UsageLedger.__dataclass_fields__})
        except Exception:
            logger.warning("[claude_code] failed to load usage ledger", exc_info=True)

    def _save_usage(self) -> None:
        try:
            _atomic_write_json(self._usage_path, self.usage.to_dict())
        except Exception:
            logger.warning("[claude_code] failed to persist usage ledger", exc_info=True)

    # -- projects ----------------------------------------------------------
    async def list_projects(self) -> List[Dict[str, Any]]:
        projects = load_projects()
        out: List[Dict[str, Any]] = []
        for p in projects:
            git = await self._git_summary(p.path)
            out.append({**p.to_dict(), "git": git})
        return out

    # -- session CRUD ------------------------------------------------------
    async def create_session(self, project: str, permission_mode: Optional[str] = None, title: str = "") -> Session:
        proj = resolve_project(project)
        if proj is None:
            raise ValueError(f"unknown project: {project!r}")
        mode = permission_mode if permission_mode in _ALLOWED_MODES else _DEFAULT_MODE
        async with self._lock:
            if len(self._sessions) >= _MAX_SESSIONS:
                # prune the oldest idle session
                idle = sorted((s for s in self._sessions.values() if s.status != "running"), key=lambda s: s.updated_at)
                if idle:
                    self._sessions.pop(idle[0].id, None)
            sid = f"ccs_{uuid.uuid4().hex[:12]}"
            sess = Session(id=sid, project=proj.name, cwd=proj.path, permission_mode=mode, title=title or proj.name)
            self._sessions[sid] = sess
            self._save()
            return sess

    def get_session(self, session_id: str) -> Optional[Session]:
        return self._sessions.get(session_id)

    def list_sessions(self) -> List[Dict[str, Any]]:
        return [s.to_dict() for s in sorted(self._sessions.values(), key=lambda s: s.updated_at, reverse=True)]

    async def delete_session(self, session_id: str) -> bool:
        async with self._lock:
            await self.interrupt(session_id)
            existed = self._sessions.pop(session_id, None) is not None
            if existed:
                self._save()
            return existed

    async def interrupt(self, session_id: str) -> bool:
        # Fail any pending permission requests closed so the CLI's blocked MCP
        # call unblocks and the process can exit cleanly.
        self._resolve_all_pending(session_id, allow=False, message="Interrupted.")
        proc = self._running.get(session_id)
        if proc is None:
            return False
        try:
            proc.terminate()
        except ProcessLookupError:
            pass
        except Exception:
            logger.debug("[claude_code] terminate failed", exc_info=True)
        return True

    # -- permission bridge (approve mode) ----------------------------------
    async def _ensure_uds(self) -> None:
        """Lazily start the Unix-domain-socket server the permission MCP calls
        back into. One server serves all sessions; requests carry the session id
        and a per-turn nonce."""
        if self._uds_server is not None:
            return
        Path(self._uds_path).parent.mkdir(parents=True, exist_ok=True)
        try:
            if os.path.exists(self._uds_path):
                os.unlink(self._uds_path)
        except OSError:
            pass
        self._uds_server = await asyncio.start_unix_server(self._on_uds_conn, path=self._uds_path)
        try:
            os.chmod(self._uds_path, 0o600)
        except OSError:
            pass

    async def _on_uds_conn(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            line = await reader.readline()
            if not line:
                return
            req = json.loads(line.decode("utf-8"))
            decision = await self._handle_permission_request(req)
            writer.write((json.dumps(decision) + "\n").encode("utf-8"))
            await writer.drain()
        except Exception:
            logger.debug("[claude_code] uds conn error", exc_info=True)
            try:
                writer.write(b'{"behavior":"deny","message":"bridge error"}\n')
                await writer.drain()
            except Exception:
                pass
        finally:
            try:
                writer.close()
            except Exception:
                pass

    async def _handle_permission_request(self, req: Dict[str, Any]) -> Dict[str, Any]:
        sid = req.get("session_id", "")
        token = req.get("token", "")
        tuid = req.get("tool_use_id") or f"perm_{uuid.uuid4().hex[:8]}"
        tool = req.get("tool_name", "tool")
        inp = req.get("input", {})
        turn = self._turns.get(sid)
        if turn is None or not secrets.compare_digest(str(token), turn.perm_token):
            return {"behavior": "deny", "message": "no active turn for this session"}
        loop = asyncio.get_running_loop()
        fut: "asyncio.Future" = loop.create_future()
        turn.pending[tuid] = (fut, inp)
        await turn.queue.put({
            "type": "permission.request",
            "tool_use_id": tuid,
            "tool": tool,
            "summary": _permission_summary(tool, inp),
            "input": _preview_input(inp, limit=1200),
        })
        try:
            return await asyncio.wait_for(fut, timeout=_PERM_TIMEOUT)
        except asyncio.TimeoutError:
            return {"behavior": "deny", "message": "Approval timed out."}
        finally:
            turn.pending.pop(tuid, None)

    def resolve_permission(self, session_id: str, tool_use_id: str, allow: bool, message: str = "") -> bool:
        """Called by the REST layer when the phone taps Allow/Deny."""
        turn = self._turns.get(session_id)
        if turn is None:
            return False
        entry = turn.pending.get(tool_use_id)
        if entry is None:
            return False
        fut, inp = entry
        if fut.done():
            return False
        if allow:
            fut.set_result({"behavior": "allow", "updatedInput": inp})
        else:
            fut.set_result({"behavior": "deny", "message": message or "Denied from phone."})
        return True

    def _resolve_all_pending(self, session_id: str, allow: bool, message: str) -> None:
        turn = self._turns.get(session_id)
        if turn is None:
            return
        for _tuid, (fut, inp) in list(turn.pending.items()):
            if fut.done():
                continue
            fut.set_result(
                {"behavior": "allow", "updatedInput": inp} if allow
                else {"behavior": "deny", "message": message}
            )

    # -- turn streaming ----------------------------------------------------
    async def stream_turn(
        self,
        session_id: str,
        prompt: str,
        permission_mode: Optional[str] = None,
    ) -> AsyncIterator[Dict[str, Any]]:
        """Run one user turn and yield normalised events.

        In ``approve`` mode the CLI is launched with a permission MCP bridge; the
        stdout event stream and out-of-band ``permission.request`` events are
        multiplexed onto one queue. Terminates after the CLI's ``result`` (or an
        ``error``).
        """
        sess = self._sessions.get(session_id)
        if sess is None:
            yield {"type": "error", "message": "unknown session"}
            return
        if sess.status == "running":
            yield {"type": "error", "message": "a turn is already running for this session"}
            return

        mode = permission_mode if permission_mode in _ALLOWED_MODES else sess.permission_mode
        turn = _Turn(perm_token=secrets.token_hex(16))

        argv = [_claude_bin(), "--print", "--output-format", "stream-json", "--verbose"]
        if mode == "approve":
            # Run the CLI in default mode but route every gated tool through our
            # permission MCP so the phone approves each action.
            await self._ensure_uds()
            script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "permission_mcp.py")
            mcp_cfg = json.dumps({"mcpServers": {"atlantic": {
                "command": sys.executable,
                "args": [script],
                "env": {
                    "HERMES_CC_SOCK": self._uds_path,
                    "HERMES_CC_SESSION": session_id,
                    "HERMES_CC_TOKEN": turn.perm_token,
                },
            }}})
            argv += ["--permission-mode", "default",
                     "--mcp-config", mcp_cfg,
                     "--permission-prompt-tool", _PERM_TOOL]
        else:
            argv += ["--permission-mode", mode]
        model = _configured_model()
        if model:
            argv += ["--model", model]
        if sess.claude_session_id:
            argv += ["--resume", sess.claude_session_id]
        argv.append(prompt)

        sess.status = "running"
        sess.permission_mode = mode
        sess.updated_at = time.time()
        self._save()
        self._turns[session_id] = turn

        proc: Optional[asyncio.subprocess.Process] = None
        reader_task: Optional[asyncio.Task] = None
        try:
            proc = await asyncio.create_subprocess_exec(
                *argv,
                cwd=sess.cwd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL,
                env=os.environ.copy(),
                limit=_STREAM_LIMIT,
            )
            self._running[session_id] = proc
            reader_task = asyncio.create_task(self._read_proc(proc, sess, turn))
            while True:
                item = await turn.queue.get()
                if item is _TURN_DONE:
                    break
                yield item
        except FileNotFoundError:
            sess.status = "error"
            yield {"type": "error", "message": "claude CLI not found — set claude_code.claude_bin in config.yaml"}
        except asyncio.CancelledError:
            if proc is not None:
                try:
                    proc.terminate()
                except Exception:
                    pass
            raise
        except Exception as exc:
            sess.status = "error"
            logger.exception("[claude_code] turn failed")
            yield {"type": "error", "message": str(exc)[:_MAX_RESULT_PREVIEW]}
        finally:
            self._resolve_all_pending(session_id, allow=False, message="Turn ended.")
            if proc is not None and proc.returncode is None:
                try:
                    proc.terminate()
                except Exception:
                    pass
            if reader_task is not None and not reader_task.done():
                reader_task.cancel()
            self._running.pop(session_id, None)
            self._turns.pop(session_id, None)
            if sess.status == "running":
                sess.status = "idle"
            sess.turns += 1
            sess.updated_at = time.time()
            self._save()

    async def _read_proc(self, proc: asyncio.subprocess.Process, sess: Session, turn: _Turn) -> None:
        """Read the CLI's stdout, normalise events onto the turn queue, and post
        the terminal sentinel. Runs as a background task so permission events can
        interleave on the same queue."""
        saw_result = False
        try:
            assert proc.stdout is not None
            while True:
                try:
                    raw = await proc.stdout.readline()
                except (asyncio.LimitOverrunError, ValueError):
                    logger.warning("[claude_code] oversized stream line skipped")
                    continue
                if not raw:
                    break
                line = raw.decode("utf-8", "replace").strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except Exception:
                    continue
                for norm in self._normalise(sess, ev):
                    if norm.get("type") == "turn.result":
                        saw_result = True
                    await turn.queue.put(norm)
            await proc.wait()
            if not saw_result:
                stderr = b""
                try:
                    if proc.stderr is not None:
                        stderr = await proc.stderr.read()
                except Exception:
                    pass
                msg = stderr.decode("utf-8", "replace").strip() or f"claude exited with code {proc.returncode}"
                sess.status = "error"
                await turn.queue.put({"type": "error", "message": msg[:_MAX_RESULT_PREVIEW]})
        except asyncio.CancelledError:
            pass
        except Exception:
            logger.exception("[claude_code] reader failed")
        finally:
            await turn.queue.put(_TURN_DONE)

    def _normalise(self, sess: Session, ev: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Map one CLI stream-json event to zero or more phone-facing events."""
        t = ev.get("type")
        st = ev.get("subtype", "")
        out: List[Dict[str, Any]] = []

        if t == "system" and st == "init":
            csid = ev.get("session_id")
            if csid and not sess.claude_session_id:
                sess.claude_session_id = csid
                self._save()
            out.append({
                "type": "session.init",
                "claude_session_id": csid,
                "model": ev.get("model"),
                "permission_mode": ev.get("permissionMode"),
                "cwd": ev.get("cwd"),
            })
        elif t == "assistant":
            for b in (ev.get("message", {}).get("content") or []):
                bt = b.get("type")
                if bt == "text" and b.get("text"):
                    out.append({"type": "assistant.text", "text": b["text"]})
                elif bt == "thinking":
                    out.append({"type": "assistant.thinking"})
                elif bt == "tool_use" and b.get("name") == "ExitPlanMode":
                    # Plan mode: the model presents its plan by calling
                    # ExitPlanMode (the tool itself is disabled in headless mode
                    # and the call errors, but its input carries the clean
                    # structured plan). Surface it as a first-class event.
                    inp = b.get("input")
                    plan = str(inp.get("plan") or "") if isinstance(inp, dict) else ""
                    out.append({"type": "plan.ready", "plan": plan[:8000]})
                elif bt == "tool_use":
                    out.append({
                        "type": "tool.started",
                        "tool": b.get("name"),
                        "tool_id": b.get("id"),
                        "input": _preview_input(b.get("input")),
                    })
        elif t == "user":
            for b in (ev.get("message", {}).get("content") or []):
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    content = b.get("content")
                    preview = content if isinstance(content, str) else json.dumps(content, ensure_ascii=False)
                    out.append({
                        "type": "tool.result",
                        "tool_id": b.get("tool_use_id"),
                        "is_error": bool(b.get("is_error")),
                        "preview": (preview or "")[:800],
                    })
        elif t == "system" and st == "post_turn_summary":
            if ev.get("status_detail"):
                out.append({"type": "turn.summary", "text": ev.get("status_detail")})
        elif t == "rate_limit_event":
            # Passive, free side-channel from real turns — used only for the
            # LIVE in-session indicator. `/usage` polling (below) is the
            # authoritative usage source and the sole reset-notification
            # trigger; this just needs the freshest snapshot recorded.
            info = ev.get("rate_limit_info") or {}
            payload = {
                "type": "rate_limit.status",
                "status": info.get("status"),
                "resets_at": info.get("resetsAt"),
                "rate_limit_type": info.get("rateLimitType"),
                "is_using_overage": info.get("isUsingOverage"),
            }
            self.usage.last_rate_limit = {**payload, "observed_at": time.time()}
            self._save_usage()
            out.append(payload)
        elif t == "result":
            denials = ev.get("permission_denials") or []
            cost = ev.get("total_cost_usd")
            out.append({
                "type": "turn.result",
                "is_error": bool(ev.get("is_error")),
                "result": (ev.get("result") or "")[:_MAX_RESULT_PREVIEW],
                "denials": [{"tool": d.get("tool_name"), "input": _preview_input(d.get("tool_input"))} for d in denials],
                "num_turns": ev.get("num_turns"),
                "cost_usd": cost,
            })
            sess.last_result = (ev.get("result") or "")[:400]
            if isinstance(cost, (int, float)):
                self.usage.total_cost_usd += cost
                self.usage.per_project_cost_usd[sess.project] = (
                    self.usage.per_project_cost_usd.get(sess.project, 0.0) + cost
                )
                self.usage.total_turns += 1
                self._save_usage()
        return out

    # -- /usage polling (free, zero-token usage checks) --------------------
    def ensure_usage_poller_started(self) -> None:
        """Lazily start the periodic `/usage` poll loop. No-ops if already
        running, or if no projects are configured yet (nothing to poll for)."""
        if self._poll_task is not None and not self._poll_task.done():
            return
        if not load_projects():
            return
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            return
        self._poll_task = loop.create_task(self._usage_poll_loop())

    async def _usage_poll_loop(self) -> None:
        interval = _usage_poll_interval()
        while True:
            try:
                await self.refresh_usage()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("[claude_code] usage poll failed")
            await asyncio.sleep(interval)

    async def refresh_usage(self) -> Dict[str, Any]:
        """Run the CLI's `/usage` command and update the ledger.

        Verified zero-cost: the CLI answers with a synthetic (non-model)
        message — `"model":"<synthetic>"`, `total_cost_usd: 0`, all token
        counts 0 — so this is safe to poll on a timer, unlike a real turn.
        Works from any directory (account-level, not project-scoped) and
        needs no folder-trust prompt.
        """
        argv = [_claude_bin(), "--print", "--output-format", "stream-json", "--verbose",
                "--permission-mode", "plan", "/usage"]
        text = ""
        try:
            proc = await asyncio.create_subprocess_exec(
                *argv,
                cwd=str(_hermes_home()),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL,
                env=os.environ.copy(),
                limit=_STREAM_LIMIT,
            )
            out, _err = await asyncio.wait_for(proc.communicate(), timeout=60)
        except Exception as exc:
            logger.warning("[claude_code] /usage check failed: %s", exc)
            return self.usage_snapshot()
        for line in out.decode("utf-8", "replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if ev.get("type") == "assistant":
                for b in ev.get("message", {}).get("content", []) or []:
                    if b.get("type") == "text":
                        text += b.get("text", "")
        parsed = _parse_usage_text(text)
        if parsed:
            for event in self._update_usage_from_check(parsed):
                asyncio.create_task(self._notify_reset(event))
        else:
            logger.debug("[claude_code] /usage reply didn't match the expected format")
        return self.usage_snapshot()

    def _update_usage_from_check(self, parsed: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Compare a fresh `/usage` reading against the last one and detect
        resets, independently per window (session / week).

        Primary signal: the window's ``resets_at`` rolled over to a new value
        after the previous one had passed. Fallback: usage percentage dropped
        sharply (covers a missed poll spanning the actual reset moment, where
        both old and new ``resets_at`` might already be in the future)."""
        now = time.time()
        prev = self.usage.last_check or {}
        events: List[Dict[str, Any]] = []
        for window in ("session", "week"):
            pct_key, resets_key = f"{window}_used_pct", f"{window}_resets_at"
            prev_pct, prev_resets = prev.get(pct_key), prev.get(resets_key)
            new_pct, new_resets = parsed.get(pct_key), parsed.get(resets_key)
            if new_pct is None:
                continue
            reset_detected = False
            if prev_resets and new_resets and prev_resets != new_resets and now >= prev_resets:
                reset_detected = True
            elif prev_pct is not None and prev_pct >= 50 and new_pct < prev_pct - 20:
                reset_detected = True
            if reset_detected:
                events.append({
                    "at": now,
                    "window": window,
                    "resets_at": new_resets,
                    "used_pct": new_pct,
                })
        self.usage.last_check = {**parsed, "observed_at": now}
        if events:
            self.usage.reset_events.extend(events)
            self.usage.reset_events = self.usage.reset_events[-20:]
        self._save_usage()
        return events

    async def _notify_reset(self, event: Dict[str, Any]) -> None:
        """Push an ntfy alert when a `/usage` reset is detected. Best-effort —
        failures are logged, never raised (this runs as a detached task).

        Hermes delivers proactive pushes two ways: a ``platforms.ntfy`` config
        block, OR plain ``NTFY_*`` env vars (the reminders/briefings path). We
        support both: resolve a platform config if present (respecting an
        explicit disable), otherwise fall through to ``_standalone_send``'s
        env-var fallback (``NTFY_HOME_CHANNEL`` / ``NTFY_TOPIC``)."""
        try:
            from plugins.platforms.ntfy.adapter import _standalone_send as ntfy_send

            pconfig = None
            chat_id = ""
            try:
                from gateway.config import Platform, load_gateway_config
                config = load_gateway_config()
                platform = Platform("ntfy")
                pconfig = config.platforms.get(platform)
                if pconfig is not None and not pconfig.enabled:
                    logger.info("[claude_code] usage reset detected but ntfy platform is disabled")
                    return
                home = config.get_home_channel(platform)
                chat_id = home.chat_id if home else ""
            except Exception:
                logger.debug("[claude_code] no ntfy platform config; using env fallback", exc_info=True)
            # Env fallback so the alert lands on the same topic as the user's
            # other proactive pushes even without a platforms.ntfy block.
            chat_id = chat_id or os.getenv("NTFY_HOME_CHANNEL", "") or os.getenv("NTFY_TOPIC", "")
            window = "5-hour session" if event.get("window") == "session" else "weekly"
            message = f"Claude Code {window} usage limit has reset — you can code again."
            result = await ntfy_send(pconfig, chat_id, message, title="Claude Code")
            if result.get("error"):
                logger.warning("[claude_code] reset notify failed: %s", result["error"])
        except Exception:
            logger.exception("[claude_code] failed to send reset notification")

    def usage_snapshot(self) -> Dict[str, Any]:
        """Cumulative usage + current status, for the REST endpoint. ``*_pct``/
        ``*_resets_at``/``*_resets_in_seconds`` come from the free `/usage`
        poll (authoritative); ``last_rate_limit`` is the passive live-turn
        signal (may be None until a turn has run)."""
        lc = self.usage.last_check or {}
        now = time.time()

        def _resets_in(key: str) -> Optional[float]:
            val = lc.get(key)
            return max(0.0, val - now) if isinstance(val, (int, float)) else None

        return {
            "total_cost_usd": round(self.usage.total_cost_usd, 4),
            "total_turns": self.usage.total_turns,
            "per_project_cost_usd": {k: round(v, 4) for k, v in self.usage.per_project_cost_usd.items()},
            "session_used_pct": lc.get("session_used_pct"),
            "session_resets_at": lc.get("session_resets_at"),
            "session_resets_in_seconds": _resets_in("session_resets_at"),
            "week_used_pct": lc.get("week_used_pct"),
            "week_resets_at": lc.get("week_resets_at"),
            "week_resets_in_seconds": _resets_in("week_resets_at"),
            "usage_checked_at": lc.get("observed_at"),
            "last_rate_limit": self.usage.last_rate_limit,
            "reset_events": list(reversed(self.usage.reset_events[-10:])),
        }

    # -- git helpers -------------------------------------------------------
    async def _git(self, cwd: str, *args: str) -> tuple[int, str, str]:
        try:
            proc = await asyncio.create_subprocess_exec(
                "git", "-C", cwd, *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            out, err = await proc.communicate()
            return proc.returncode or 0, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")
        except Exception as exc:
            return 1, "", str(exc)

    async def _git_summary(self, cwd: str) -> Dict[str, Any]:
        code, out, _ = await self._git(cwd, "status", "--porcelain=v1", "-b")
        if code != 0:
            return {"is_repo": False}
        lines = out.splitlines()
        branch = ""
        dirty = 0
        if lines and lines[0].startswith("##"):
            branch = lines[0][2:].strip().split("...")[0].strip()
            dirty = len(lines) - 1
        else:
            dirty = len(lines)
        return {"is_repo": True, "branch": branch, "dirty": dirty}

    async def git_diff(self, session_id: str) -> Dict[str, Any]:
        sess = self._sessions.get(session_id)
        if sess is None:
            raise ValueError("unknown session")
        _, stat, _ = await self._git(sess.cwd, "diff", "--stat", "HEAD")
        _, diff, _ = await self._git(sess.cwd, "diff", "HEAD")
        _, untracked, _ = await self._git(sess.cwd, "ls-files", "--others", "--exclude-standard")
        return {
            "stat": stat,
            "diff": diff,
            "untracked": [u for u in untracked.splitlines() if u.strip()],
        }

    async def commit(self, session_id: str, message: str, push: bool = False) -> Dict[str, Any]:
        """Stage all, commit, optionally push. Gated: only called on explicit
        phone approval by the REST layer."""
        sess = self._sessions.get(session_id)
        if sess is None:
            raise ValueError("unknown session")
        add_code, _, add_err = await self._git(sess.cwd, "add", "-A")
        if add_code != 0:
            return {"ok": False, "stage": "add", "error": add_err}
        code, out, err = await self._git(sess.cwd, "commit", "-m", message)
        if code != 0:
            return {"ok": False, "stage": "commit", "error": err or out}
        result: Dict[str, Any] = {"ok": True, "commit": out.strip()}
        if push:
            pcode, pout, perr = await self._git(sess.cwd, "push")
            result["push"] = {"ok": pcode == 0, "output": (pout + perr).strip()}
        return result

    async def _gh(self, cwd: str, *args: str) -> tuple[int, str, str]:
        try:
            proc = await asyncio.create_subprocess_exec(
                "gh", *args, cwd=cwd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            out, err = await proc.communicate()
            return proc.returncode or 0, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")
        except FileNotFoundError:
            return 127, "", "gh CLI not installed on the gateway host"
        except Exception as exc:
            return 1, "", str(exc)

    async def open_pr(self, session_id: str, title: str = "", body: str = "", push: bool = True) -> Dict[str, Any]:
        """Push the current branch and open a PR via ``gh``. Gated: only called
        on explicit phone approval."""
        sess = self._sessions.get(session_id)
        if sess is None:
            raise ValueError("unknown session")
        result: Dict[str, Any] = {}
        if push:
            pcode, pout, perr = await self._git(sess.cwd, "push", "-u", "origin", "HEAD")
            result["push"] = {"ok": pcode == 0, "output": (pout + perr).strip()}
            if pcode != 0:
                return {"ok": False, "stage": "push", **result}
        args = ["pr", "create", "--fill"] if not title else ["pr", "create", "--title", title, "--body", body or title]
        code, out, err = await self._gh(sess.cwd, *args)
        if code != 0:
            return {"ok": False, "stage": "pr", "error": (err or out).strip(), **result}
        return {"ok": True, "url": out.strip(), **result}


def _permission_summary(tool: str, inp: Any) -> str:
    """A short human line describing what the CLI is asking to do."""
    if not isinstance(inp, dict):
        return tool
    if tool == "Bash":
        return str(inp.get("command", ""))[:400]
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit", "Update"):
        return str(inp.get("file_path") or inp.get("path") or tool)
    if tool == "Read":
        return str(inp.get("file_path", ""))
    return tool


def _preview_input(inp: Any, limit: int = 300) -> Any:
    if inp is None:
        return None
    try:
        s = json.dumps(inp, ensure_ascii=False)
    except Exception:
        s = str(inp)
    return s[:limit]


_MANAGER: Optional[ClaudeCodeManager] = None


def get_manager() -> ClaudeCodeManager:
    global _MANAGER
    if _MANAGER is None:
        _MANAGER = ClaudeCodeManager()
    return _MANAGER
