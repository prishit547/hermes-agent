"""YouTube media resolution via yt-dlp — the Music capability's source.

Ported from Atlantic OS (`backend/app/integrations/youtube.py`). Two jobs, kept
separate for latency:

* :func:`search` — lightweight, *flat* search that returns candidate tracks
  (id/title/artist/duration/thumbnail) without resolving any stream. ~1s.
* :func:`resolve` — turn one video id into a direct **best-audio** stream URL plus
  the HTTP headers YouTube expects. The ``/music/stream`` proxy replays these so
  the client plays seekable audio (no CORS, no client-side yt-dlp).

yt-dlp is blocking, so every call runs in a worker thread. Covers both
``youtube.com`` and ``music.youtube.com`` (ytsearch reaches both catalogues).

yt-dlp itself is an opt-in dependency — it is lazily installed on first use via
``tools.lazy_deps`` (feature key ``music.youtube``), so plain installs don't
carry it until the music feature is actually exercised.
"""
from __future__ import annotations

import asyncio
import logging
import os
import re
import time
from dataclasses import dataclass, field
from typing import Optional

log = logging.getLogger("hermes.music.youtube")

# Player clients tried in order until one yields a playable https audio URL.
# ``None`` = yt-dlp's default web client (works without a JS runtime for most
# tracks); android is a resilient fallback. DRM-only clients (tv) are omitted.
_CLIENT_FALLBACKS: list[Optional[list[str]]] = [None, ["android"], ["web_safari"]]
_AUDIO_FORMAT = "bestaudio[ext=m4a]/bestaudio/best"

# Resolved googlevideo URLs are IP/time-bound; re-resolve well before they lapse.
_RESOLVE_TTL = 30 * 60  # seconds

_BASE_OPTS: dict = {
    "quiet": True,
    "no_warnings": True,
    "skip_download": True,
    "noplaylist": True,
    "cachedir": False,
}


def _yt_dlp():
    """Import yt-dlp, lazily installing it on first use.

    Kept out of module scope so a bare ``import plugins.music.youtube`` (e.g. the
    plugin loader inspecting the package) never triggers an install or fails on a
    host that has never used the music feature.
    """
    try:
        from tools import lazy_deps

        lazy_deps.ensure("music.youtube", prompt=False)
    except Exception as exc:  # noqa: BLE001 — fall through to a plain import
        log.debug("music: lazy ensure for yt-dlp skipped: %s", exc)
    import yt_dlp  # noqa: PLC0415

    return yt_dlp


def _base_opts() -> dict:
    """Base yt-dlp options + an authenticated cookies file when configured.

    A logged-in ``cookies.txt`` (Netscape format, exported from a YouTube
    session) cuts bot-check/throttle failures and unlocks age-gated tracks. Point
    ``HERMES_YOUTUBE_COOKIES`` at it. It does NOT provide personalized
    recommendations — yt-dlp is a downloader, not a rec API. The option is
    additive and per-call, so a missing/stale file just degrades to anonymous
    access rather than hard-failing.
    """
    opts = dict(_BASE_OPTS)
    cookies = (os.environ.get("HERMES_YOUTUBE_COOKIES") or "").strip()
    if cookies:
        opts["cookiefile"] = cookies
    return opts


@dataclass
class Track:
    """A searchable/queueable music item (no stream URL — see :func:`resolve`)."""

    video_id: str
    title: str
    artist: str
    duration: float  # seconds
    thumbnail: str

    def to_dict(self) -> dict:
        return {
            "videoId": self.video_id,
            "title": self.title,
            "artist": self.artist,
            "duration": self.duration,
            "thumbnail": self.thumbnail,
            "source": "youtube",
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Track":
        return cls(
            video_id=d.get("videoId") or d.get("video_id") or "",
            title=d.get("title") or "Unknown title",
            artist=d.get("artist") or "Unknown artist",
            duration=float(d.get("duration") or 0),
            thumbnail=d.get("thumbnail") or "",
        )


@dataclass
class Resolved:
    """A direct audio stream ready for the proxy to replay."""

    url: str
    headers: dict = field(default_factory=dict)
    mime: str = "audio/mp4"
    expires: float = 0.0


_resolve_cache: dict[str, Resolved] = {}


def _thumb(video_id: str) -> str:
    # Deterministic and always present, unlike flat-search thumbnail arrays.
    return f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"


def _clean_artist(name: str) -> str:
    # YouTube auto-generated artist channels are named "Artist - Topic".
    return re.sub(r"\s*-\s*Topic$", "", (name or "").strip()) or "Unknown artist"


def _entry_to_track(e: dict) -> Optional[Track]:
    vid = e.get("id")
    if not vid:
        return None
    return Track(
        video_id=vid,
        title=(e.get("title") or "Unknown title").strip(),
        artist=_clean_artist(e.get("uploader") or e.get("channel") or ""),
        duration=float(e.get("duration") or 0),
        thumbnail=e.get("thumbnail") or _thumb(vid),
    )


def _search_sync(query: str, limit: int) -> list[Track]:
    yt_dlp = _yt_dlp()
    opts = {**_base_opts(), "extract_flat": True, "default_search": "ytsearch"}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(f"ytsearch{limit}:{query}", download=False)
    entries = (info or {}).get("entries") or []
    tracks = [t for e in entries if (t := _entry_to_track(e))]
    # Drop obvious non-music noise (livestreams have duration 0).
    return [t for t in tracks if t.duration > 0]


def _mime_for(ext: str, acodec: str) -> str:
    if ext in ("webm", "opus") or "opus" in (acodec or ""):
        return "audio/webm"
    return "audio/mp4"


def _resolve_sync(video_id: str) -> Resolved:
    yt_dlp = _yt_dlp()
    url = f"https://www.youtube.com/watch?v={video_id}"
    last_err: Optional[Exception] = None
    for clients in _CLIENT_FALLBACKS:
        opts = {**_base_opts(), "format": _AUDIO_FORMAT}
        if clients:
            opts["extractor_args"] = {"youtube": {"player_client": clients}}
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(url, download=False)
        except Exception as exc:  # noqa: BLE001 — try the next client
            last_err = exc
            continue
        stream_url = info.get("url")
        if not stream_url:
            continue
        # googlevideo URLs carry ?expire=<unix>; honour it, else fall back to TTL.
        m = re.search(r"[?&]expire=(\d+)", stream_url)
        expires = float(m.group(1)) - 60 if m else time.time() + _RESOLVE_TTL
        return Resolved(
            url=stream_url,
            headers=info.get("http_headers") or {},
            mime=_mime_for(info.get("ext", ""), info.get("acodec", "")),
            expires=expires,
        )
    raise RuntimeError(f"could not resolve audio for {video_id}: {last_err}")


async def search(query: str, limit: int = 6) -> list[Track]:
    """Search YouTube for music matching ``query`` (fast, no stream resolution)."""
    query = (query or "").strip()
    if not query:
        return []
    return await asyncio.to_thread(_search_sync, query, max(1, min(limit, 15)))


async def resolve(video_id: str, *, force: bool = False) -> Resolved:
    """Resolve a direct best-audio stream URL for ``video_id`` (cached ~30m)."""
    cached = _resolve_cache.get(video_id)
    if cached and not force and cached.expires > time.time():
        return cached
    resolved = await asyncio.to_thread(_resolve_sync, video_id)
    _resolve_cache[video_id] = resolved
    return resolved


async def top_result(query: str) -> Optional[Track]:
    """The single best match for a spoken 'play X' request."""
    results = await search(query, limit=1)
    return results[0] if results else None


def _extract_mix_sync(video_id: str) -> list[dict]:
    yt_dlp = _yt_dlp()
    url = f"https://www.youtube.com/watch?v={video_id}&list=RD{video_id}"
    opts = {**_base_opts(), "noplaylist": False, "extract_flat": True, "playlist_items": "1-15"}
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
        return (info or {}).get("entries") or []
    except Exception as e:  # noqa: BLE001
        log.warning("Failed to extract Mix playlist for %s: %s", video_id, e)
        return []


def is_duplicate_song(orig_title: str, orig_artist: str, cand_title: str, cand_artist: str) -> bool:
    def normalize(s: str) -> str:
        s = s.lower()
        # Remove common suffixes
        s = re.sub(r"\(official\s*(video|audio|lyrics?|music\s*video|hd|hq)?\)", "", s)
        s = re.sub(r"\[official\s*(video|audio|lyrics?|music\s*video|hd|hq)?\]", "", s)
        s = re.sub(r"\b(lyric\s*video|lyrics|official\s*audio|official\s*video|official|extended\s*mix|extended|original\s*mix|original|live\s*version|live|hd|hq|hqdefault|cover)\b", "", s)
        # Remove special characters
        s = re.sub(r"[^\w\s]", "", s)
        # Remove spaces
        return "".join(s.split())

    orig_title_norm = normalize(orig_title)
    cand_title_norm = normalize(cand_title)

    # If the candidate title is exactly or almost identical to original title
    if orig_title_norm == cand_title_norm:
        return True

    # If they are very similar length and one contains the other
    if len(orig_title_norm) > 4 and len(cand_title_norm) > 4:
        if orig_title_norm in cand_title_norm or cand_title_norm in orig_title_norm:
            return True

    return False


async def get_recommendations(video_id: str, title: str, artist: str, limit: int = 10) -> list[Track]:
    entries = await asyncio.to_thread(_extract_mix_sync, video_id)
    tracks: list[Track] = []
    seen_ids = {video_id}

    for e in entries:
        track = _entry_to_track(e)
        if not track:
            continue
        if track.video_id in seen_ids:
            continue
        # Filter duplicates (different versions of same song)
        if is_duplicate_song(title, artist, track.title, track.artist):
            continue

        seen_ids.add(track.video_id)
        tracks.append(track)
        if len(tracks) >= limit:
            break

    return tracks
