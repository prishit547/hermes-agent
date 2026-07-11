"""Music integration plugin — bundled, auto-loaded.

Registers a single ``music`` tool (play / search / enqueue / recommend /
transport / likes / playlists) into the ``music`` toolset. Music streams from
YouTube via ``yt-dlp`` (no API key); the gateway proxies audio at
``/music/stream/<id>`` and the Flutter app plays it. Ported from Atlantic OS.

A plugin (not a top-level ``tools/`` file) because it is a multi-module service
integration — mirrors ``plugins/spotify/``. Bundled + ``kind: backend``
auto-loads on startup, no user opt-in.
"""

from __future__ import annotations

from plugins.music.tools import MUSIC_HANDLER, MUSIC_SCHEMA, check_music_requirements


def register(ctx) -> None:
    """Register the music tool. Called once by the plugin loader."""
    ctx.register_tool(
        name="music",
        toolset="music",
        schema=MUSIC_SCHEMA,
        handler=MUSIC_HANDLER,
        check_fn=check_music_requirements,
        is_async=True,
        emoji="🎵",
    )
