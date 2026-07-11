#!/usr/bin/env python3
"""Shared audio HTTP helpers for Hermes' two servers.

Both the localhost dashboard server (``hermes_cli/web_server.py``, FastAPI,
port 9119) and the OpenAI-compatible API server
(``gateway/platforms/api_server.py``, aiohttp, port 8642) expose speech
endpoints. Keeping the decode / transcribe / synthesize logic here means the
two servers behave identically and stay in sync — a fix to one fixes both.

All functions here are **synchronous** and CPU/IO-blocking (model inference,
file writes, subprocess audio conversion). Async callers must run them off the
event loop, e.g. ``await loop.run_in_executor(None, transcribe_audio_bytes, ...)``.

Framework-agnostic on purpose: failures raise :class:`AudioRequestError`
(carrying an HTTP status + detail) rather than any web framework's exception,
so each server maps it to its own response type.
"""
from __future__ import annotations

import base64
import binascii
import json as _json
import os
import tempfile
from typing import Optional, Tuple

# Upload ceiling for a single transcription request. Note the API server also
# bounds the whole request body (``MAX_REQUEST_BYTES``, ~10 MB) before a handler
# runs, so that is the effective cap there; this is a defensive per-payload
# guard shared by both servers.
MAX_TRANSCRIPTION_UPLOAD_BYTES = 25 * 1024 * 1024

# MIME → temp-file suffix for uploaded recordings. faster-whisper / Parakeet
# and the ffmpeg normalization path key off the extension, so an accurate
# suffix matters. Mirrors the browser MediaRecorder output types.
AUDIO_MIME_EXTENSIONS = {
    "audio/aac": ".aac",
    "audio/flac": ".flac",
    "audio/m4a": ".m4a",
    "audio/mp3": ".mp3",
    "audio/mp4": ".mp4",
    "audio/mpeg": ".mp3",
    "audio/ogg": ".ogg",
    "audio/wav": ".wav",
    "audio/wave": ".wav",
    "audio/webm": ".webm",
    "audio/x-m4a": ".m4a",
    "audio/x-wav": ".wav",
    "video/webm": ".webm",
}

# Synthesized-audio file extension → response MIME type.
SPEECH_MIME_TYPES = {
    ".mp3": "audio/mpeg",
    ".ogg": "audio/ogg",
    ".opus": "audio/ogg",
    ".wav": "audio/wav",
    ".flac": "audio/flac",
}


class AudioRequestError(Exception):
    """Framework-agnostic audio failure carrying an HTTP status + detail.

    Each server catches this and maps ``status_code``/``detail`` onto its own
    error response (FastAPI ``HTTPException`` or aiohttp ``web.json_response``).
    """

    def __init__(self, status_code: int, detail: str):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


def audio_extension_for_mime(mime_type: str) -> str:
    """Return a temp-file suffix for an audio MIME type (default ``.webm``)."""
    normalized = (mime_type or "").split(";", 1)[0].strip().lower()
    return AUDIO_MIME_EXTENSIONS.get(normalized, ".webm")


def _validate_audio_bytes(audio_bytes: bytes) -> bytes:
    if not audio_bytes:
        raise AudioRequestError(400, "Audio recording is empty")
    if len(audio_bytes) > MAX_TRANSCRIPTION_UPLOAD_BYTES:
        raise AudioRequestError(413, "Audio recording is too large")
    return audio_bytes


def decode_audio_data_url(
    data_url: str, mime_type: Optional[str] = None
) -> Tuple[bytes, str]:
    """Decode a ``data:audio/...;base64,<data>`` URL into (bytes, mime_type).

    Accepts an explicit ``mime_type`` override (used by clients that send the
    MIME separately from the data URL). Raises :class:`AudioRequestError` with
    a 400 on any malformed input, or 413 when the decoded audio is too large.
    """
    data_url = (data_url or "").strip()
    if not data_url.startswith("data:") or "," not in data_url:
        raise AudioRequestError(400, "Invalid audio payload")

    header, encoded = data_url.split(",", 1)
    if ";base64" not in header:
        raise AudioRequestError(400, "Audio payload must be base64 encoded")

    resolved_mime = (mime_type or header[5:].split(";", 1)[0] or "audio/webm").strip()
    normalized = resolved_mime.split(";", 1)[0].lower()
    if not (normalized.startswith("audio/") or normalized == "video/webm"):
        raise AudioRequestError(400, "Payload must be an audio recording")

    try:
        audio_bytes = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise AudioRequestError(400, "Audio payload is not valid base64")

    return _validate_audio_bytes(audio_bytes), resolved_mime


def transcribe_audio_bytes(audio_bytes: bytes, mime_type: str) -> dict:
    """Transcribe raw audio bytes. Returns ``{"transcript", "provider"}``.

    Writes the bytes to a temp file with a MIME-appropriate suffix, runs the
    configured STT provider (``tools.transcription_tools.transcribe_audio``),
    then removes the temp file. Raises :class:`AudioRequestError` on failure.
    """
    _validate_audio_bytes(audio_bytes)

    from tools.transcription_tools import transcribe_audio

    suffix = audio_extension_for_mime(mime_type)
    temp_path = ""
    try:
        with tempfile.NamedTemporaryFile(
            prefix="hermes-voice-", suffix=suffix, delete=False
        ) as tmp:
            tmp.write(audio_bytes)
            temp_path = tmp.name
        result = transcribe_audio(temp_path)
    finally:
        if temp_path:
            try:
                os.unlink(temp_path)
            except OSError:
                pass

    if not result.get("success"):
        raise AudioRequestError(400, result.get("error") or "Transcription failed")

    return {
        "transcript": str(result.get("transcript") or "").strip(),
        "provider": result.get("provider"),
    }


def synthesize_speech(text: str) -> Tuple[bytes, str, Optional[str]]:
    """Synthesize speech from text. Returns (audio_bytes, mime_type, provider).

    Reuses the configured TTS provider chain
    (``tools.tts_tool.text_to_speech_tool``: Edge / Piper / OpenAI /
    ElevenLabs / …), reads the produced file into memory, and deletes it.
    Raises :class:`AudioRequestError` on failure.
    """
    text = (text or "").strip()
    if not text:
        raise AudioRequestError(400, "Text is required")

    from tools.tts_tool import text_to_speech_tool

    try:
        result_json = text_to_speech_tool(text)
    except Exception as exc:  # pragma: no cover - provider-specific failures
        raise AudioRequestError(500, f"Speech synthesis failed: {exc}")

    try:
        result = _json.loads(result_json) if isinstance(result_json, str) else result_json
    except Exception:
        raise AudioRequestError(500, "Invalid TTS response")

    if not result.get("success"):
        raise AudioRequestError(400, result.get("error") or "Speech synthesis failed")

    file_path = result.get("file_path")
    if not file_path or not os.path.isfile(file_path):
        raise AudioRequestError(500, "Audio file missing")

    ext = os.path.splitext(file_path)[1].lower()
    mime_type = SPEECH_MIME_TYPES.get(ext, "audio/mpeg")

    try:
        with open(file_path, "rb") as fh:
            audio_bytes = fh.read()
    except OSError as exc:
        raise AudioRequestError(500, f"Could not read audio: {exc}")
    finally:
        try:
            os.unlink(file_path)
        except OSError:
            pass

    return audio_bytes, mime_type, result.get("provider")


def speech_data_url(audio_bytes: bytes, mime_type: str) -> str:
    """Encode synthesized audio as a ``data:<mime>;base64,...`` URL."""
    encoded = base64.b64encode(audio_bytes).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def _elevenlabs_api_key() -> str:
    key = (os.environ.get("ELEVENLABS_API_KEY") or "").strip()
    if key:
        return key
    try:
        from hermes_cli.config import load_env

        return (load_env().get("ELEVENLABS_API_KEY") or "").strip()
    except Exception:
        return ""


def _elevenlabs_voice_label(voice: dict) -> str:
    name = str(voice.get("name") or voice.get("voice_id") or "Voice").strip()
    category = str(voice.get("category") or "").strip()
    return f"{name} ({category})" if category else name


def list_elevenlabs_voices() -> dict:
    """Return ``{"available": bool, "voices": [...]}`` for the TTS voice picker.

    Only non-secret voice metadata is returned; the API key stays server-side.
    Returns ``available: False`` (not an error) when no key is configured or the
    key is unauthorized, so callers can render an empty dropdown gracefully.
    """
    import urllib.error
    import urllib.request

    api_key = _elevenlabs_api_key()
    if not api_key:
        return {"available": False, "voices": []}

    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/voices",
        headers={"Accept": "application/json", "xi-api-key": api_key},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            payload = _json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            return {"available": False, "voices": [], "error": "unauthorized"}
        raise AudioRequestError(502, "Could not load ElevenLabs voices")
    except Exception:
        raise AudioRequestError(502, "Could not load ElevenLabs voices")

    voices = []
    for voice in payload.get("voices") or []:
        if not isinstance(voice, dict):
            continue
        voice_id = str(voice.get("voice_id") or "").strip()
        if not voice_id:
            continue
        voices.append({
            "voice_id": voice_id,
            "name": str(voice.get("name") or voice_id),
            "label": _elevenlabs_voice_label(voice),
        })
    voices.sort(key=lambda item: str(item.get("label") or "").lower())
    return {"available": True, "voices": voices}
