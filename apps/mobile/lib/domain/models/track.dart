/// A single music track (a YouTube result) and the player's now-playing
/// snapshot, mirroring the backend shapes in `plugins/music` (`Track.to_dict`
/// and `MusicPlayer.snapshot`). Plain immutable value types with `fromJson`.
class Track {
  const Track({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnail,
  });

  final String videoId;
  final String title;
  final String artist;
  final double duration; // seconds
  final String thumbnail;

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        videoId: (j['videoId'] ?? j['video_id'] ?? '').toString(),
        title: (j['title'] ?? 'Unknown title').toString(),
        artist: (j['artist'] ?? 'Unknown artist').toString(),
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        thumbnail: (j['thumbnail'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'duration': duration,
        'thumbnail': thumbnail,
      };
}

/// The server's authoritative view of what's loaded — current track, queue, and
/// play/pause intent. `version` bumps on every change so the app can cheaply
/// detect agent-driven playback by polling `/api/music/now-playing`.
class PlayerSnapshot {
  const PlayerSnapshot({
    required this.hasTrack,
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.duration,
    required this.isPlaying,
    required this.position,
    required this.queue,
    required this.index,
    required this.version,
  });

  final bool hasTrack;
  final String? videoId;
  final String title;
  final String artist;
  final String? thumbnail;
  final double duration;
  final bool isPlaying;
  final double position;
  final List<Track> queue;
  final int index;
  final int version;

  static const empty = PlayerSnapshot(
    hasTrack: false,
    videoId: null,
    title: 'Nothing playing',
    artist: '—',
    thumbnail: null,
    duration: 0,
    isPlaying: false,
    position: 0,
    queue: [],
    index: -1,
    version: 0,
  );

  Track? get current => hasTrack && videoId != null
      ? Track(
          videoId: videoId!,
          title: title,
          artist: artist,
          duration: duration,
          thumbnail: thumbnail ?? '',
        )
      : null;

  factory PlayerSnapshot.fromJson(Map<String, dynamic> j) => PlayerSnapshot(
        hasTrack: j['hasTrack'] == true,
        videoId: j['videoId'] as String?,
        title: (j['title'] ?? 'Nothing playing').toString(),
        artist: (j['artist'] ?? '—').toString(),
        thumbnail: j['thumbnail'] as String?,
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        isPlaying: j['isPlaying'] == true,
        position: (j['position'] as num?)?.toDouble() ?? 0,
        queue: (j['queue'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Track.fromJson)
            .toList(),
        index: (j['index'] as num?)?.toInt() ?? -1,
        version: (j['version'] as num?)?.toInt() ?? 0,
      );
}
