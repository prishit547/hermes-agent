"""In-memory music player state (single-user, single-session).

Ported from Atlantic OS (`backend/app/core/music_player.py`). The *client* owns
real playback (a persistent audio element in the Flutter app); this holds the
agent's view of **what** is loaded — current track, queue, and the play/pause
intent — so both the REST endpoints and the agent tool drive one place. Live
position is advisory (the client reports truth); everything else is truth.
"""
from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from typing import Optional

from plugins.music import youtube
from plugins.music.youtube import Track

log = logging.getLogger("hermes.music.player")


def _fmt(seconds: float) -> str:
    seconds = max(0, int(seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


@dataclass
class MusicPlayer:
    queue: list[Track] = field(default_factory=list)
    index: int = -1
    is_playing: bool = False
    position: float = 0.0  # advisory last-known playback second
    version: int = 0       # bumps on every state change (clients poll this)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock, repr=False)

    # --- derived ---
    @property
    def current(self) -> Optional[Track]:
        if 0 <= self.index < len(self.queue):
            return self.queue[self.index]
        return None

    def _touch(self) -> None:
        self.version += 1

    # --- mutations ---
    async def play_query(self, query: str) -> Optional[Track]:
        """Search YouTube and start the top hit; the queue is then seeded with
        recommendations in the background."""
        results = await youtube.search(query, limit=1)
        if not results:
            return None
        track = results[0]
        async with self._lock:
            self.queue = [track]
            self.index = 0
            self.is_playing = True
            self.position = 0.0
            self._touch()
        asyncio.create_task(self._load_recommendations_async(track))
        log.info("music: playing %r -> %s (loading radio in background)", query, track.title)
        return self.current

    async def enqueue_query(self, query: str) -> Optional[Track]:
        top = await youtube.top_result(query)
        if not top:
            return None
        async with self._lock:
            self.queue.append(top)
            if self.index < 0:
                self.index = 0
                self.is_playing = True
            self._touch()
        return top

    async def play_track(self, track: Track) -> Track:
        async with self._lock:
            self.queue = [track]
            self.index = 0
            self.is_playing = True
            self.position = 0.0
            self._touch()
        asyncio.create_task(self._load_recommendations_async(track))
        log.info("music: play_track %s (loading radio in background)", track.title)
        return track

    async def _load_recommendations_async(self, track: Track) -> None:
        try:
            recommendations = await youtube.get_recommendations(
                track.video_id, track.title, track.artist, limit=10
            )
            async with self._lock:
                if self.current and self.current.video_id == track.video_id:
                    user_enqueued = self.queue[self.index + 1:]
                    seen = {r.video_id for r in recommendations}
                    filtered = [t for t in user_enqueued if t.video_id not in seen]
                    self.queue = self.queue[:self.index + 1] + recommendations + filtered
                    self._touch()
                    log.info("music: loaded %d radio tracks for %s", len(recommendations), track.title)
        except Exception as e:  # noqa: BLE001
            log.warning("music: failed to load radio in background: %s", e)

    async def enqueue_track(self, track: Track) -> Track:
        async with self._lock:
            self.queue.append(track)
            if self.index < 0:
                self.index = 0
                self.is_playing = True
            self._touch()
        return track

    def clear_queue(self) -> None:
        self.queue = []
        self.index = -1
        self.is_playing = False
        self.position = 0.0
        self._touch()

    def remove_from_queue(self, idx: int) -> None:
        if 0 <= idx < len(self.queue):
            self.queue.pop(idx)
            if len(self.queue) == 0:
                self.index = -1
                self.is_playing = False
                self.position = 0.0
            elif self.index == idx:
                if self.index >= len(self.queue):
                    self.index = len(self.queue) - 1
                self.position = 0.0
            elif self.index > idx:
                self.index -= 1
            self._touch()

    def reorder_queue(self, from_idx: int, to_idx: int) -> None:
        if 0 <= from_idx < len(self.queue) and 0 <= to_idx < len(self.queue):
            current_track = self.current
            track = self.queue.pop(from_idx)
            self.queue.insert(to_idx, track)
            if current_track in self.queue:
                self.index = self.queue.index(current_track)
            self._touch()

    def play_index(self, idx: int) -> Optional[Track]:
        if 0 <= idx < len(self.queue):
            self.index = idx
            self.is_playing = True
            self.position = 0.0
            self._touch()
        return self.current

    def upcoming_count(self) -> int:
        """How many tracks remain after the current one (for endless radio)."""
        if self.index < 0:
            return 0
        return max(0, len(self.queue) - 1 - self.index)

    async def extend_queue(self, tracks: list[Track]) -> int:
        """Append fresh tracks to the END of the queue, skipping any already
        present (by video id). Used by the recommender for continuous radio."""
        if not tracks:
            return 0
        async with self._lock:
            have = {t.video_id for t in self.queue}
            fresh = [t for t in tracks if t.video_id not in have]
            self.queue.extend(fresh)
            if fresh:
                self._touch()
        if fresh:
            log.info("music: extend_queue +%d (endless radio)", len(fresh))
        return len(fresh)

    async def play_playlist_tracks(self, tracks: list[Track]) -> None:
        async with self._lock:
            self.queue = list(tracks)
            self.index = 0 if tracks else -1
            self.is_playing = bool(tracks)
            self.position = 0.0
            self._touch()
        log.info("music: play_playlist_tracks count=%d", len(tracks))

    def toggle(self) -> bool:
        if self.current:
            self.is_playing = not self.is_playing
            self._touch()
        return self.is_playing

    def set_playing(self, playing: bool) -> None:
        if self.current:
            self.is_playing = playing
            self._touch()

    def next(self) -> Optional[Track]:
        if self.index + 1 < len(self.queue):
            self.index += 1
            self.is_playing = True
            self.position = 0.0
            self._touch()
        return self.current

    def previous(self) -> Optional[Track]:
        # Restart the track if we're past the intro, else step back.
        if self.position > 3 or self.index <= 0:
            self.position = 0.0
        else:
            self.index -= 1
        self.is_playing = True
        self._touch()
        return self.current

    def stop(self) -> None:
        self.is_playing = False
        self.position = 0.0
        self._touch()

    def seek(self, position: float) -> None:
        self.position = max(0.0, position)
        self._touch()

    def report(self, position: float, is_playing: bool) -> None:
        """The client tells us where playback actually is."""
        self.position = max(0.0, position)
        if self.current:
            self.is_playing = is_playing

    # --- serialization ---
    def snapshot(self) -> dict:
        cur = self.current
        queue_dicts = [t.to_dict() for t in self.queue]
        if not cur:
            return {
                "videoId": None, "title": "Nothing playing", "artist": "—",
                "thumbnail": None, "duration": 0, "streamUrl": None,
                "isPlaying": False, "hasTrack": False, "position": 0.0,
                "queue": [], "index": -1, "version": self.version,
                "elapsed": "0:00", "remaining": "0:00", "progress": 0.0,
            }
        dur = cur.duration or 0
        progress = (self.position / dur) if dur else 0.0
        return {
            "videoId": cur.video_id,
            "title": cur.title,
            "artist": cur.artist,
            "thumbnail": cur.thumbnail,
            "duration": dur,
            "streamUrl": f"/music/stream/{cur.video_id}",
            "isPlaying": self.is_playing,
            "hasTrack": True,
            "position": self.position,
            "queue": queue_dicts,
            "index": self.index,
            "version": self.version,
            "elapsed": _fmt(self.position),
            "remaining": f"-{_fmt(max(0, dur - self.position))}",
            "progress": min(1.0, max(0.0, progress)),
        }


# Process-wide singleton (single-user system).
player = MusicPlayer()
