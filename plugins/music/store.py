"""Music persistence — listening history + playlists, JSON-backed.

Replaces Atlantic OS's SQL layer (`music_history` + `playlists`) with flat JSON
files under ``~/.hermes/music/`` — Hermes has no ORM and the house style for tool
state is ``get_hermes_home()`` + an atomic write (see ``tools/skill_usage.py``).

* ``events.json``   — every listening signal (play/complete/skip/like/dislike);
  the recommender + taste profile read these back to learn what the user enjoys.
* ``playlists.json``— user playlists.

Signal weighting (shared by taste + ranking):
    liked      +3.0
    completed  +1.0
    played     +0.25   (started but outcome unknown)
    skipped    -1.0    (only when barely played)
    disliked   -3.0
"""
from __future__ import annotations

import json
import logging
import os
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any, Optional

from hermes_constants import get_hermes_home

log = logging.getLogger("hermes.music.store")

EVENT_WEIGHT = {
    "liked": 3.0,
    "completed": 1.0,
    "played": 0.25,
    "skipped": -1.0,   # only when played_fraction < SKIP_NEG_FRACTION
    "disliked": -3.0,
}
SKIP_NEG_FRACTION = 0.35  # a skip after this much play isn't really a dislike
_MAX_EVENTS = 5000        # keep the file bounded; oldest rows drop off


# --------------------------------------------------------------------------- #
#  Paths + atomic IO (mirrors tools/skill_usage.py)                            #
# --------------------------------------------------------------------------- #
def _music_dir() -> Path:
    return get_hermes_home() / "music"


def _events_file() -> Path:
    return _music_dir() / "events.json"


def _playlists_file() -> Path:
    return _music_dir() / "playlists.json"


def _load(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        log.debug("music: failed reading %s: %s", path, e)
        return default


def _save(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), prefix=".music_", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)  # atomic
    except Exception:  # noqa: BLE001 — best-effort; never break playback
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


# --------------------------------------------------------------------------- #
#  Listening history                                                           #
# --------------------------------------------------------------------------- #
def record_event(
    *,
    video_id: str,
    title: str = "",
    artist: str = "",
    duration: float = 0.0,
    thumbnail: str | None = None,
    event: str,
    played_fraction: float = 0.0,
    position: float = 0.0,
    source: str = "youtube",
) -> None:
    """Append one interaction row. Best-effort — never raises to the caller."""
    if not video_id or event not in EVENT_WEIGHT:
        return
    try:
        events = _load(_events_file(), [])
        if not isinstance(events, list):
            events = []
        events.append({
            "videoId": video_id,
            "title": (title or "")[:400],
            "artist": (artist or "")[:300],
            "duration": float(duration or 0.0),
            "thumbnail": thumbnail or None,
            "event": event,
            "playedFraction": max(0.0, min(1.0, float(played_fraction or 0.0))),
            "position": float(position or 0.0),
            "source": source or "youtube",
            "ts": time.time(),
        })
        if len(events) > _MAX_EVENTS:
            events = events[-_MAX_EVENTS:]
        _save(_events_file(), events)
    except Exception as exc:  # noqa: BLE001
        log.warning("music: record_event failed: %s", exc)


def _events(limit: int = 1000) -> list[dict]:
    events = _load(_events_file(), [])
    if not isinstance(events, list):
        return []
    return events[-limit:][::-1]  # most recent first


def _weight(ev: dict) -> float:
    w = EVENT_WEIGHT.get(ev.get("event", ""), 0.0)
    if ev.get("event") == "skipped" and (ev.get("playedFraction") or 0.0) >= SKIP_NEG_FRACTION:
        return 0.0  # skipped near the end ~ neutral, not a dislike
    return w


def _ids_for_event(event: str, *, limit: int = 300) -> set[str]:
    out: set[str] = set()
    for ev in _events(2000):
        if ev.get("event") == event and ev.get("videoId"):
            out.add(ev["videoId"])
            if len(out) >= limit:
                break
    return out


def disliked_video_ids(*, limit: int = 300) -> set[str]:
    return _ids_for_event("disliked", limit=limit)


def liked_video_ids(*, limit: int = 300) -> set[str]:
    """Video ids liked and not later disliked."""
    return _ids_for_event("liked", limit=limit) - disliked_video_ids()


def recently_played_ids(*, limit: int = 80) -> set[str]:
    """Video ids seen recently (any play/completion) — for novelty filtering."""
    out: set[str] = set()
    for ev in _events(2000):
        if ev.get("event") in ("played", "completed") and ev.get("videoId"):
            out.add(ev["videoId"])
            if len(out) >= limit:
                break
    return out


def top_artists(*, limit: int = 12) -> list[str]:
    """Artists ranked by accumulated affinity weight (desc)."""
    scores: dict[str, float] = {}
    for ev in _events(1000):
        artist = ev.get("artist")
        if not artist:
            continue
        scores[artist] = scores.get(artist, 0.0) + _weight(ev)
    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    return [a for a, s in ranked if s > 0][:limit]


def top_tracks(*, limit: int = 40) -> list[dict]:
    """Distinct tracks ranked by affinity weight (desc). Returns track dicts."""
    scores: dict[str, float] = {}
    meta: dict[str, dict] = {}
    for ev in _events(1000):
        vid = ev.get("videoId")
        if not vid:
            continue
        scores[vid] = scores.get(vid, 0.0) + _weight(ev)
        if vid not in meta or (ev.get("title") and not meta[vid].get("title")):
            meta[vid] = {
                "videoId": vid, "title": ev.get("title", ""), "artist": ev.get("artist", ""),
                "duration": ev.get("duration", 0.0), "thumbnail": ev.get("thumbnail"),
            }
    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    return [meta[v] for v, s in ranked if s > 0][:limit]


def profile() -> dict:
    """The listener's taste profile — top artists + top tracks (no embeddings)."""
    return {"top_artists": top_artists(), "top_tracks": top_tracks()}


# --------------------------------------------------------------------------- #
#  Playlists                                                                   #
# --------------------------------------------------------------------------- #
def get_playlists() -> list[dict]:
    data = _load(_playlists_file(), {"playlists": []})
    if isinstance(data, dict):
        return data.get("playlists", [])
    return data if isinstance(data, list) else []


def _save_playlists(playlists: list[dict]) -> None:
    _save(_playlists_file(), {"playlists": playlists})


def create_playlist(name: str, description: str = "") -> dict:
    playlists = get_playlists()
    new_pl = {"id": str(uuid.uuid4()), "name": name, "description": description, "tracks": []}
    playlists.append(new_pl)
    _save_playlists(playlists)
    return new_pl


def delete_playlist(playlist_id: str) -> bool:
    playlists = get_playlists()
    filtered = [p for p in playlists if p.get("id") != playlist_id]
    if len(filtered) == len(playlists):
        return False
    _save_playlists(filtered)
    return True


def find_playlist(playlist_id: str) -> Optional[dict]:
    for pl in get_playlists():
        if pl.get("id") == playlist_id:
            return pl
    return None


def add_track_to_playlist(playlist_id: str, track: dict) -> Optional[dict]:
    playlists = get_playlists()
    for pl in playlists:
        if pl.get("id") == playlist_id:
            if any(t.get("videoId") == track.get("videoId") for t in pl["tracks"]):
                return pl
            pl["tracks"].append({
                "videoId": track["videoId"],
                "title": track.get("title", ""),
                "artist": track.get("artist", ""),
                "duration": float(track.get("duration") or 0),
                "thumbnail": track.get("thumbnail", ""),
            })
            _save_playlists(playlists)
            return pl
    return None


def remove_track_from_playlist(playlist_id: str, video_id: str) -> Optional[dict]:
    playlists = get_playlists()
    for pl in playlists:
        if pl.get("id") == playlist_id:
            pl["tracks"] = [t for t in pl["tracks"] if t.get("videoId") != video_id]
            _save_playlists(playlists)
            return pl
    return None
