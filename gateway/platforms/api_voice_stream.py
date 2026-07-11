"""Realtime hands-free voice pipeline over a WebSocket (``/v1/voice/stream``).

This is the full-duplex counterpart to the request/response ``/v1/audio/*``
endpoints. A single bidirectional socket carries:

- **up:** binary audio frames (one complete WAV utterance, the phone runs local
  VAD and endpointing) plus JSON control frames (``commit``/``barge_in``/…);
- **down:** JSON frames (``final_transcript``, ``assistant_delta``,
  ``turn_complete``) interleaved with binary TTS audio frames.

Barge-in — the user talking over the assistant — is just the existing agent
interrupt triggered by an inbound WS message instead of a POST to
``/v1/runs/{id}/stop``: the client sends ``{"type":"barge_in"}`` and we call
``agent.interrupt()`` (via the ``agent_ref`` captured from ``_run_agent``) and
stop emitting TTS.

The heavy lifting (agent turn + streaming deltas, STT, TTS) is **reused**, not
re-implemented: ``adapter._run_agent`` for the turn, and
``tools.audio_endpoints_core`` for transcription/synthesis.

Protocol
--------
Client → server:
  - binary frame(s): audio for the current utterance (a complete WAV blob).
  - ``{"type":"commit"}``     — utterance finished; transcribe + answer.
  - ``{"type":"barge_in"}``   — user started speaking over the reply; interrupt.
  - ``{"type":"cancel"}``     — abort the current turn and drop buffered audio.
  - ``{"type":"reset"}``      — clear the audio buffer without answering.

Server → client:
  - ``{"type":"ready"}``                       — on connect.
  - ``{"type":"final_transcript","text":...}``  — recognized user utterance.
  - ``{"type":"assistant_delta","text":...}``   — streamed reply text.
  - ``{"type":"tts_start","mime":...}`` … binary audio frames … ``{"type":"tts_end"}``
  - ``{"type":"turn_complete"}``
  - ``{"type":"error","message":...}``
"""

from __future__ import annotations

import asyncio
import hmac
import json
import logging
import re
import uuid
from typing import Any, List, Optional

try:
    from aiohttp import WSMsgType, web
except Exception:  # pragma: no cover - aiohttp is a hard dep of the api_server
    web = None  # type: ignore[assignment]
    WSMsgType = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)

# TTS audio is sent in frames of at most this size so the phone can start
# buffering/playing before the whole clip is transferred.
_TTS_FRAME_BYTES = 16 * 1024

# Synthesize as soon as a sentence completes for low latency, rather than
# waiting for the whole reply. Matches sentence-final punctuation + trailing
# space/end so we don't cut mid-number ("3.14") or mid-abbreviation too eagerly.
_SENTENCE_RE = re.compile(r".+?[.!?…](?:\s+|$)", re.DOTALL)


def _extract_sentences(buffer: str) -> tuple[List[str], str]:
    """Split ``buffer`` into complete sentences + the trailing remainder."""
    sentences: List[str] = []
    last_end = 0
    for match in _SENTENCE_RE.finditer(buffer):
        sentences.append(match.group().strip())
        last_end = match.end()
    return sentences, buffer[last_end:]


class VoiceStreamHandler:
    """Owns one ``/v1/voice/stream`` connection's lifecycle.

    A fresh instance per connection keeps per-turn state (barge-in flag, the
    active agent ref, the running turn task, conversation history) isolated.
    """

    def __init__(self, adapter: Any):
        self._adapter = adapter

    # -- auth ---------------------------------------------------------------

    def _authorized(self, request: "web.Request") -> bool:
        """Bearer header (preferred) or ``?token=`` query fallback for clients
        that can't set WS handshake headers."""
        if self._adapter._check_auth(request) is None:
            return True
        api_key = getattr(self._adapter, "_api_key", "")
        token = request.query.get("token", "")
        return bool(api_key and hmac.compare_digest(token, api_key))

    # -- entrypoint ---------------------------------------------------------

    async def handle(self, request: "web.Request") -> "web.StreamResponse":
        if not self._authorized(request):
            return web.json_response(
                {"error": {"message": "Invalid API key", "type": "invalid_request_error"}},
                status=401,
            )

        ws = web.WebSocketResponse(heartbeat=30, max_msg_size=0)
        await ws.prepare(request)

        loop = asyncio.get_running_loop()
        session_id = request.query.get("session_id") or f"voice-{uuid.uuid4()}"
        history: List[dict] = []
        audio_buffer = bytearray()

        # Mutable per-turn state shared with the running turn task so an inbound
        # barge_in/cancel can reach into the active agent + stop TTS.
        state: dict = {"agent_ref": None, "cancel_tts": False}
        turn_task: Optional[asyncio.Task] = None

        await ws.send_json({"type": "ready", "session_id": session_id})

        try:
            async for msg in ws:
                if msg.type == WSMsgType.BINARY:
                    audio_buffer.extend(msg.data)
                    continue
                if msg.type != WSMsgType.TEXT:
                    if msg.type in (WSMsgType.ERROR, WSMsgType.CLOSE):
                        break
                    continue

                try:
                    data = json.loads(msg.data)
                except Exception:
                    continue
                mtype = data.get("type")

                if mtype == "commit":
                    if not audio_buffer:
                        continue
                    # A new utterance supersedes any in-flight reply.
                    self._interrupt(state)
                    if turn_task and not turn_task.done():
                        turn_task.cancel()
                    utterance = bytes(audio_buffer)
                    audio_buffer.clear()
                    state["cancel_tts"] = False
                    turn_task = asyncio.ensure_future(
                        self._process_utterance(ws, utterance, history, session_id, state, loop)
                    )
                elif mtype == "barge_in":
                    self._interrupt(state)
                elif mtype == "cancel":
                    self._interrupt(state)
                    audio_buffer.clear()
                    if turn_task and not turn_task.done():
                        turn_task.cancel()
                elif mtype == "reset":
                    audio_buffer.clear()
        finally:
            self._interrupt(state)
            if turn_task and not turn_task.done():
                turn_task.cancel()
            if not ws.closed:
                await ws.close()
        return ws

    # -- barge-in -----------------------------------------------------------

    def _interrupt(self, state: dict) -> None:
        """Interrupt the active agent turn and stop TTS emission."""
        state["cancel_tts"] = True
        agent_ref = state.get("agent_ref")
        agent = agent_ref[0] if agent_ref else None
        if agent is not None:
            try:
                agent.interrupt("barge-in")
            except Exception:
                logger.debug("agent.interrupt() during barge-in failed", exc_info=True)

    # -- one turn -----------------------------------------------------------

    async def _process_utterance(
        self,
        ws: "web.WebSocketResponse",
        audio_bytes: bytes,
        history: List[dict],
        session_id: str,
        state: dict,
        loop: "asyncio.AbstractEventLoop",
    ) -> None:
        from tools.audio_endpoints_core import (
            AudioRequestError,
            transcribe_audio_bytes,
        )

        # 1. Speech-to-text (Parakeet / faster-whisper), off the event loop.
        try:
            result = await loop.run_in_executor(
                None, transcribe_audio_bytes, audio_bytes, "audio/wav"
            )
            transcript = (result.get("transcript") or "").strip()
        except AudioRequestError as exc:
            await self._safe_send(ws, {"type": "error", "message": exc.detail})
            return
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("voice stream: transcription failed")
            await self._safe_send(ws, {"type": "error", "message": "Transcription failed"})
            return

        await self._safe_send(ws, {"type": "final_transcript", "text": transcript})
        if not transcript:
            await self._safe_send(ws, {"type": "turn_complete"})
            return

        # 2. Agent turn with streamed deltas. The delta callback runs in the
        #    agent's worker thread, so hop back to the loop thread-safely.
        delta_q: asyncio.Queue = asyncio.Queue()

        def _on_delta(delta: str) -> None:
            loop.call_soon_threadsafe(delta_q.put_nowait, ("delta", delta))

        agent_ref: list = [None]
        state["agent_ref"] = agent_ref

        agent_task = asyncio.ensure_future(
            self._adapter._run_agent(
                user_message=transcript,
                conversation_history=list(history),
                session_id=session_id,
                stream_delta_callback=_on_delta,
                agent_ref=agent_ref,
                gateway_session_key=session_id,
            )
        )
        agent_task.add_done_callback(
            lambda fut: loop.call_soon_threadsafe(delta_q.put_nowait, ("done", fut))
        )

        # 3. Drain deltas: stream text down and synthesize sentence-by-sentence.
        reply = ""
        pending = ""
        try:
            while True:
                kind, val = await delta_q.get()
                if kind == "done":
                    break
                if kind != "delta" or not val:
                    continue
                reply += val
                pending += val
                await self._safe_send(ws, {"type": "assistant_delta", "text": val})
                sentences, pending = _extract_sentences(pending)
                for sentence in sentences:
                    if state.get("cancel_tts"):
                        break
                    await self._speak(ws, sentence, state, loop)
            # Flush any trailing partial sentence.
            if pending.strip() and not state.get("cancel_tts"):
                await self._speak(ws, pending.strip(), state, loop)
        except asyncio.CancelledError:
            self._interrupt(state)
            raise
        finally:
            state["agent_ref"] = None
            # Surface any agent-side error without crashing the socket.
            try:
                await agent_task
            except asyncio.CancelledError:
                pass
            except Exception:
                logger.debug("voice stream: agent task raised", exc_info=True)

        # Thread multi-turn context within this voice session.
        if reply.strip():
            history.append({"role": "user", "content": transcript})
            history.append({"role": "assistant", "content": reply.strip()})

        await self._safe_send(ws, {"type": "turn_complete"})

    # -- tts ----------------------------------------------------------------

    async def _speak(
        self,
        ws: "web.WebSocketResponse",
        text: str,
        state: dict,
        loop: "asyncio.AbstractEventLoop",
    ) -> None:
        """Synthesize one sentence and stream it as framed binary audio.

        Best-effort: a synthesis failure is swallowed (the text already landed)
        and honors the barge-in flag before and during emission.
        """
        if state.get("cancel_tts") or not text:
            return
        from tools.audio_endpoints_core import synthesize_speech

        try:
            audio_bytes, mime_type, _provider = await loop.run_in_executor(
                None, synthesize_speech, text
            )
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.debug("voice stream: TTS failed for a sentence", exc_info=True)
            return

        if state.get("cancel_tts") or not audio_bytes or ws.closed:
            return

        await self._safe_send(ws, {"type": "tts_start", "mime": mime_type})
        for offset in range(0, len(audio_bytes), _TTS_FRAME_BYTES):
            if state.get("cancel_tts") or ws.closed:
                break
            await ws.send_bytes(audio_bytes[offset : offset + _TTS_FRAME_BYTES])
        await self._safe_send(ws, {"type": "tts_end"})

    # -- helpers ------------------------------------------------------------

    @staticmethod
    async def _safe_send(ws: "web.WebSocketResponse", payload: dict) -> None:
        if ws.closed:
            return
        try:
            await ws.send_json(payload)
        except Exception:
            logger.debug("voice stream: send failed", exc_info=True)


def register_voice_routes(app: "web.Application", adapter: Any) -> None:
    """Register the realtime voice WebSocket route on the api_server app.

    Called from ``APIServerPlatform.connect()``. A fresh handler per request so
    connection state never leaks between sockets.
    """
    async def _voice_ws(request: "web.Request") -> "web.StreamResponse":
        return await VoiceStreamHandler(adapter).handle(request)

    app.router.add_get("/v1/voice/stream", _voice_ws)
