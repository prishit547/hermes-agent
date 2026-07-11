"""The `music` agent tool — one compressed action tool.

Ported from Atlantic OS's music MCP server. Exposes YouTube playback to the model
through a single ``music`` tool with an ``action`` enum (mirroring the
``google_calendar`` tool's shape). Playback happens on the client (the Flutter
app streams ``/music/stream/<id>``); this tool mutates the shared in-memory
``player`` and the JSON ``store`` so the app reflects agent-driven playback.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Optional

from plugins.music import recommender, store
from plugins.music.player import player
from plugins.music.youtube import Track
from tools.registry import tool_error, tool_result

logger = logging.getLogger("hermes.music.tool")


MUSIC_SCHEMA = {
    "name": "music",
    "description": """Play and control music (streamed from YouTube) on the user's app.

Actions:
- action='play'          — search and play a concrete song/artist NOW (needs 'query', e.g. 'Blinding Lights'). Seeds an endless radio queue in the background.
- action='search'        — return candidate tracks for a query WITHOUT playing (needs 'query').
- action='enqueue'       — add the top hit for 'query' to the end of the queue without interrupting playback.
- action='recommend'     — build a personalized mix for a vibe/activity/'more like this' request (needs 'vibe', e.g. 'chill focus music'). Use for a *feel* rather than a specific title.
- action='pause'         — pause playback.
- action='resume'        — resume paused playback.
- action='next'          — skip to the next track.
- action='previous'      — go back (or restart the current track).
- action='stop'          — stop playback.
- action='now_playing'   — report the current track + queue.
- action='like'          — record that the user likes the current track (trains recommendations).
- action='dislike'       — record a dislike for the current track (it won't be recommended again).
- action='list_playlists'— list saved playlists (name, id, track count).
- action='create_playlist'— create a playlist (needs 'name'). Optionally pass 'query' to add a first song by name in the same step.
- action='add_to_playlist'— add a song to a playlist. Identify the playlist by 'playlist_name' (preferred) or 'playlist_id'; if that named playlist doesn't exist it is created. Pass 'query' to add a specific song by name; omit 'query' to add whatever is currently playing.
- action='play_playlist' — play a saved playlist, by 'playlist_name' or 'playlist_id'.

Prefer 'play' for a named song and 'recommend' for a vibe. For playlists you can
refer to them by name — no need to look up ids first. Example: to build a
playlist, call create_playlist with name='Workout', then add_to_playlist with
playlist_name='Workout' and query='Eye of the Tiger'.""",
    "parameters": {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": [
                    "play", "search", "enqueue", "recommend",
                    "pause", "resume", "next", "previous", "stop",
                    "now_playing", "like", "dislike",
                    "list_playlists", "create_playlist", "add_to_playlist", "play_playlist",
                ],
                "description": "The music operation to perform.",
            },
            "query": {"type": "string", "description": "Song/artist/description for play, search, enqueue."},
            "vibe": {"type": "string", "description": "For recommend: the vibe/activity/similarity request."},
            "name": {"type": "string", "description": "For create_playlist: the playlist name."},
            "description": {"type": "string", "description": "For create_playlist: optional description."},
            "playlist_name": {"type": "string", "description": "For add_to_playlist / play_playlist: the playlist name (preferred over id). Created automatically by add_to_playlist if it doesn't exist."},
            "playlist_id": {"type": "string", "description": "For add_to_playlist / play_playlist: target playlist id (alternative to playlist_name)."},
        },
        "required": ["action"],
    },
}


def _now_playing_payload() -> dict:
    return player.snapshot()


def _resolve_playlist(args: dict) -> Optional[dict]:
    """Find a playlist by id, then by (case-insensitive) name."""
    pid = (args.get("playlist_id") or "").strip()
    if pid:
        pl = store.find_playlist(pid)
        if pl:
            return pl
    name = (args.get("playlist_name") or "").strip()
    if name:
        for pl in store.get_playlists():
            if (pl.get("name") or "").strip().lower() == name.lower():
                return pl
    return None


def _record_feedback(event: str) -> str:
    cur = player.current
    if not cur:
        return tool_error("Nothing is playing to " + event + ".")
    store.record_event(
        video_id=cur.video_id, title=cur.title, artist=cur.artist,
        duration=cur.duration, thumbnail=cur.thumbnail, event=event,
    )
    verb = "Liked" if event == "liked" else "Noted — won't play again"
    return tool_result({"ok": True, "message": f"{verb}: {cur.title} by {cur.artist}."})


async def _handle(args: dict, **_kw: Any) -> str:
    action = (args.get("action") or "").strip()
    if not action:
        return tool_error("'action' is required")

    try:
        if action == "play":
            query = (args.get("query") or "").strip()
            if not query:
                return tool_error("'query' is required for play")
            track = await player.play_query(query)
            if not track:
                return tool_error(f"No results for {query!r}.")
            return tool_result({"message": f"Now playing {track.title} by {track.artist}.",
                                "nowPlaying": _now_playing_payload()})

        if action == "search":
            from plugins.music import youtube
            query = (args.get("query") or "").strip()
            if not query:
                return tool_error("'query' is required for search")
            tracks = await youtube.search(query, limit=8)
            return tool_result({"results": [t.to_dict() for t in tracks]})

        if action == "enqueue":
            query = (args.get("query") or "").strip()
            if not query:
                return tool_error("'query' is required for enqueue")
            top = await player.enqueue_query(query)
            if not top:
                return tool_error(f"No results for {query!r}.")
            return tool_result({"message": f"Queued {top.title} by {top.artist}.",
                                "nowPlaying": _now_playing_payload()})

        if action == "recommend":
            vibe = (args.get("vibe") or args.get("query") or "").strip()
            tracks = await recommender.recommend(
                seed=player.current, steer=vibe or None, use_llm=bool(vibe), limit=12,
            )
            if not tracks:
                return tool_error("Couldn't assemble a mix right now.")
            await player.play_playlist_tracks(tracks)
            return tool_result({"message": f"Started a {len(tracks)}-track mix, opening with {tracks[0].title}.",
                                "nowPlaying": _now_playing_payload()})

        if action == "pause":
            player.set_playing(False)
            return tool_result({"message": "Paused.", "nowPlaying": _now_playing_payload()})

        if action == "resume":
            if not player.current:
                return tool_error("Nothing is queued — say what to play.")
            player.set_playing(True)
            return tool_result({"message": f"Resuming {player.current.title}.",
                                "nowPlaying": _now_playing_payload()})

        if action == "next":
            prev = player.current
            track = player.next()
            if track and track is not prev:
                return tool_result({"message": f"Next up: {track.title}.", "nowPlaying": _now_playing_payload()})
            return tool_result({"message": "That's the end of the queue.", "nowPlaying": _now_playing_payload()})

        if action == "previous":
            track = player.previous()
            msg = f"Going back to {track.title}." if track else "Nothing to go back to."
            return tool_result({"message": msg, "nowPlaying": _now_playing_payload()})

        if action == "stop":
            player.stop()
            return tool_result({"message": "Stopped.", "nowPlaying": _now_playing_payload()})

        if action == "now_playing":
            return tool_result({"nowPlaying": _now_playing_payload()})

        if action == "like":
            return _record_feedback("liked")

        if action == "dislike":
            return _record_feedback("disliked")

        if action == "list_playlists":
            return tool_result({"playlists": [
                {"id": p["id"], "name": p.get("name", ""), "tracks": len(p.get("tracks", []))}
                for p in store.get_playlists()
            ]})

        if action == "create_playlist":
            name = (args.get("name") or args.get("playlist_name") or "").strip()
            if not name:
                return tool_error("'name' is required for create_playlist")
            pl = store.create_playlist(name, args.get("description") or "")
            # Optionally seed the playlist with a first song in the same call.
            added = ""
            query = (args.get("query") or "").strip()
            if query:
                from plugins.music import youtube
                top = await youtube.top_result(query)
                if top:
                    store.add_track_to_playlist(pl["id"], top.to_dict())
                    added = f" Added {top.title} by {top.artist}."
            return tool_result({
                "message": f"Created playlist {name!r}.{added}",
                "playlist": store.find_playlist(pl["id"]) or pl,
            })

        if action == "add_to_playlist":
            pl = _resolve_playlist(args)
            if not pl:
                # Auto-create when a name was given (LLM-friendly one-shot flow).
                name = (args.get("playlist_name") or args.get("name") or "").strip()
                if not name:
                    return tool_error(
                        "Playlist not found. Pass 'playlist_name' (or 'playlist_id'); "
                        "call list_playlists to see existing playlists."
                    )
                pl = store.create_playlist(name)

            # Which song? An explicit query wins; otherwise the current track.
            query = (args.get("query") or "").strip()
            if query:
                from plugins.music import youtube
                top = await youtube.top_result(query)
                if not top:
                    return tool_error(f"No results for {query!r}.")
                track_dict, label = top.to_dict(), f"{top.title} by {top.artist}"
            else:
                cur = player.current
                if not cur:
                    return tool_error(
                        "Nothing is playing — pass 'query' with the song name to add, "
                        "or start a song first."
                    )
                track_dict, label = cur.to_dict(), f"{cur.title} by {cur.artist}"

            store.add_track_to_playlist(pl["id"], track_dict)
            return tool_result({
                "message": f"Added {label} to {pl.get('name')!r}.",
                "playlist_id": pl["id"],
            })

        if action == "play_playlist":
            pl = _resolve_playlist(args)
            if not pl:
                return tool_error(
                    "Playlist not found. Pass 'playlist_name' or 'playlist_id'; "
                    "call list_playlists to see options."
                )
            tracks = [Track.from_dict(t) for t in pl.get("tracks", [])]
            if not tracks:
                return tool_error(f"Playlist {pl.get('name')!r} is empty.")
            await player.play_playlist_tracks(tracks)
            return tool_result({"message": f"Playing {pl.get('name')!r} ({len(tracks)} tracks).",
                                "nowPlaying": _now_playing_payload()})

        return tool_error(f"Unknown action: {action}")

    except Exception as exc:  # noqa: BLE001
        logger.exception("music action '%s' failed", action)
        return tool_error(f"music {action} failed: {exc}")


def check_music_requirements() -> bool:
    """Surface the tool whenever yt-dlp can be imported or lazily installed.

    yt-dlp is an opt-in dep; treat the tool as available as long as lazy installs
    aren't hard-disabled, so the model can drive playback on a fresh host.
    """
    try:
        import yt_dlp  # noqa: F401, PLC0415
        return True
    except Exception:
        pass
    try:
        from tools import lazy_deps
        return "music.youtube" in getattr(lazy_deps, "LAZY_DEPS", {})
    except Exception:
        return False


# Exported for the plugin's register(ctx) and unit tests.
MUSIC_HANDLER = _handle
