import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/music_repository.dart';
import '../../../data/services/hermes_api_client.dart';
import '../../../data/services/music_player_service.dart';
import '../../../domain/models/track.dart';

/// Drives the Music feature: search, on-device playback, queue, likes and
/// playlists. Owns the reactive glue between three sources of truth —
///  * the on-device [MusicPlayerService] (real audio + position/completion),
///  * the server [PlayerSnapshot] (queue + current, shared with the agent),
///  * agent-initiated plays, caught by polling `now-playing` while active.
/// Mirrors the load-once ChangeNotifier pattern used by Today/Email view models.
class MusicViewModel extends ChangeNotifier {
  MusicViewModel({
    required MusicRepository repository,
    required MusicPlayerService playerService,
  })  : _repo = repository,
        _svc = playerService {
    _sub.addAll([
      _svc.onPosition.listen(_onPosition),
      _svc.onDuration.listen((d) {
        _duration = d;
        notifyListeners();
      }),
      _svc.onComplete.listen((_) => _onTrackComplete()),
      // Drive the buffering spinner off the real player state so it clears the
      // moment playback is ready (the manual flag alone could get stuck).
      _svc.onBuffering.listen((b) {
        if (_buffering != b) {
          _buffering = b;
          notifyListeners();
        }
      }),
      _svc.onPlaying.listen((p) {
        if (_playing != p) {
          _playing = p;
          notifyListeners();
        }
      }),
    ]);
  }

  final MusicRepository _repo;
  final MusicPlayerService _svc;
  final List<StreamSubscription<dynamic>> _sub = [];

  PlayerSnapshot _snapshot = PlayerSnapshot.empty;
  PlayerSnapshot get snapshot => _snapshot;
  Track? get current => _snapshot.current;
  bool get hasTrack => _snapshot.hasTrack;
  List<Track> get queue => _snapshot.queue;

  List<Track> _results = [];
  List<Track> get results => List.unmodifiable(_results);

  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> get playlists => List.unmodifiable(_playlists);

  bool _searching = false;
  bool get searching => _searching;
  bool _notConnected = false;
  bool get notConnected => _notConnected;
  String? _error;
  String? get error => _error;

  bool _buffering = false;
  bool get buffering => _buffering;

  Duration _position = Duration.zero;
  Duration get position => _position;
  Duration _duration = Duration.zero;
  // Prefer the gateway's track length (from YouTube metadata) — just_audio can
  // misreport the duration of remuxed YouTube m4a streams. Fall back to the
  // decoder's value only when the server didn't provide one.
  Duration get duration {
    final serverSecs = _snapshot.duration.round();
    if (serverSecs > 0) return Duration(seconds: serverSecs);
    return _duration;
  }

  // The real player state (just_audio) — the client owns play/pause for the
  // current track; the server's isPlaying is only advisory (driven by reports).
  bool _playing = false;
  bool get isPlaying => _playing;

  // The videoId currently loaded into the on-device player, so we only reload
  // the stream when the *track* changes (not on a pause/resume/position sync).
  String? _streamingId;
  bool _screenActive = false;
  Timer? _poll;
  DateTime _lastReport = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loadedOnce = false;

  // --- lifecycle ------------------------------------------------------------

  Future<void> loadIfNeeded() async {
    if (_loadedOnce) return;
    _loadedOnce = true;
    await refresh();
    unawaited(_loadPlaylists());
  }

  Future<void> refresh() async {
    unawaited(_loadPlaylists());
    try {
      final snap = await _repo.nowPlaying();
      _notConnected = false;
      _applySnapshot(snap);
    } on HermesApiException catch (e) {
      _handleApiError(e);
    } catch (_) {
      // transient — keep prior state
    }
  }

  /// The Music screen calls this so polling only runs when it's useful
  /// (screen visible, or something is playing behind the mini-player).
  void setScreenActive(bool active) {
    final becameActive = active && !_screenActive;
    _screenActive = active;
    _syncPolling();
    // Reopening the screen should reflect anything created elsewhere (e.g. a
    // playlist the agent just made) without needing an app restart.
    if (becameActive) {
      unawaited(_loadPlaylists());
    }
  }

  void _syncPolling() {
    final want = _screenActive || _snapshot.hasTrack;
    if (want && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _pollTick());
    } else if (!want && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  int _tick = 0;

  /// Runs every 3s while active: detect agent-initiated playback (the server
  /// bumps `version` on every structural change) and, less often, pick up
  /// playlists created from another surface (the agent) so an open Music screen
  /// stays live.
  Future<void> _pollTick() async {
    _tick++;
    try {
      final snap = await _repo.nowPlaying();
      if (snap.version != _snapshot.version) {
        _applySnapshot(snap);
      }
    } catch (_) {}
    if (_tick % 3 == 0) {
      unawaited(_loadPlaylists());
    }
  }

  // --- playback actions -----------------------------------------------------

  Future<void> playQuery(String query) async {
    query = query.trim();
    if (query.isEmpty) return;
    await _guard(() async => _applySnapshot(await _repo.play(query)));
  }

  Future<void> playTrack(Track t) async {
    await _guard(() async => _applySnapshot(await _repo.playTrack(t)));
  }

  Future<void> enqueue(Track t) async {
    await _guard(() async => _applySnapshot(await _repo.enqueueTrack(t)));
  }

  Future<void> togglePlay() async {
    if (!_snapshot.hasTrack) return;
    if (_svc.isPlaying) {
      await _svc.pause();
    } else {
      await _svc.resume();
    }
    // `onPlaying` updates the UI; report the new intent to the server.
    unawaited(_repo.report(_position.inSeconds.toDouble(), _svc.isPlaying));
  }

  Future<void> next() async {
    final outgoing = current;
    if (outgoing != null) {
      unawaited(_repo.feedback(
        track: outgoing,
        event: 'skipped',
        playedFraction: _playedFraction,
        position: _position.inSeconds.toDouble(),
      ));
    }
    await _guard(() async => _applySnapshot(await _repo.control('next')));
  }

  Future<void> previous() async {
    await _guard(() async => _applySnapshot(await _repo.control('previous')));
  }

  Future<void> playIndex(int index) async {
    await _guard(() async => _applySnapshot(await _repo.control('play-index', index: index)));
  }

  Future<void> seekTo(double seconds) async {
    await _svc.seek(Duration(seconds: seconds.round()));
    _position = Duration(seconds: seconds.round());
    notifyListeners();
    unawaited(_repo.seek(seconds));
  }

  Future<void> like() async {
    final t = current;
    if (t == null) return;
    await _repo.feedback(track: t, event: 'liked');
  }

  Future<void> dislike() async {
    final t = current;
    if (t == null) return;
    await _repo.feedback(track: t, event: 'disliked');
    await next();
  }

  // --- search + playlists ---------------------------------------------------

  Future<void> search(String query) async {
    query = query.trim();
    if (query.isEmpty) {
      _results = [];
      notifyListeners();
      return;
    }
    _searching = true;
    _error = null;
    notifyListeners();
    try {
      _results = await _repo.search(query);
      _notConnected = false;
    } on HermesApiException catch (e) {
      _handleApiError(e);
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  Future<void> _loadPlaylists() async {
    try {
      final next = await _repo.playlists();
      // Only rebuild when something actually changed (this runs on a timer).
      if (!_samePlaylists(_playlists, next)) {
        _playlists = next;
        notifyListeners();
      }
    } catch (_) {}
  }

  static bool _samePlaylists(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['id'] != b[i]['id'] ||
          a[i]['name'] != b[i]['name'] ||
          (a[i]['tracks'] as List?)?.length != (b[i]['tracks'] as List?)?.length) {
        return false;
      }
    }
    return true;
  }

  Future<void> createPlaylist(String name) async {
    await _repo.createPlaylist(name);
    await _loadPlaylists();
  }

  Future<void> addCurrentToPlaylist(String playlistId) async {
    final t = current;
    if (t == null) return;
    await _repo.addToPlaylist(playlistId, t);
    await _loadPlaylists();
  }

  Future<void> playPlaylist(String playlistId) async {
    await _guard(() async => _applySnapshot(await _repo.playPlaylist(playlistId)));
  }

  Future<void> recommendMore() async {
    await _guard(() async {
      final recs = await _repo.recommendations();
      for (final t in recs.take(1)) {
        _applySnapshot(await _repo.playTrack(t));
      }
    });
  }

  // --- internals ------------------------------------------------------------

  double get _playedFraction {
    final dur = duration.inSeconds;
    return dur > 0 ? (_position.inSeconds / dur).clamp(0.0, 1.0) : 0.0;
  }

  /// Reconcile server state with the on-device player. The client owns
  /// play/pause + position for the current track (just_audio is the source of
  /// truth); we only react to *structural* changes here — a different current
  /// track means someone (the user via another surface, or the agent) chose a
  /// new song, so we stream it. We deliberately do NOT mirror the server's
  /// advisory `isPlaying` onto the local player, which would fight the client's
  /// own state (the server's isPlaying is driven by our reports).
  void _applySnapshot(PlayerSnapshot snap) {
    _snapshot = snap;
    _syncPolling();
    if (snap.hasTrack && snap.videoId != null) {
      if (snap.videoId != _streamingId) {
        _streamingId = snap.videoId;
        _position = Duration.zero;
        _duration = Duration(seconds: snap.duration.round());
        unawaited(_startPlayback(snap.videoId!, snap.current));
      }
    } else if (!snap.hasTrack) {
      _streamingId = null;
      unawaited(_svc.stop());
    }
    notifyListeners();
  }

  /// Fetch + start a freshly-selected track, surfacing a buffering state while
  /// the audio downloads and an error if it fails (so it never crashes as an
  /// unhandled async exception).
  Future<void> _startPlayback(String videoId, Track? track) async {
    _buffering = true; // immediate feedback; onBuffering clears it when ready
    _error = null;
    notifyListeners();
    try {
      await _svc.playUrl(videoId, _repo.streamUri(videoId));
      if (track != null) unawaited(_repo.feedback(track: track, event: 'played'));
    } catch (e) {
      // Only report if this is still the track we're trying to play.
      if (_streamingId == videoId) {
        _error = 'Playback failed: $e';
        _buffering = false;
        notifyListeners();
      }
    }
  }

  void _onPosition(Duration pos) {
    _position = pos;
    // Throttle the position report to the server to ~5s.
    final now = DateTime.now();
    if (now.difference(_lastReport).inSeconds >= 5) {
      _lastReport = now;
      unawaited(_repo.report(pos.inSeconds.toDouble(), _svc.isPlaying));
    }
    notifyListeners();
  }

  Future<void> _onTrackComplete() async {
    // just_audio can emit `completed` spuriously during source swaps or a brief
    // stream hiccup. Only treat it as end-of-track (and auto-advance) when the
    // track actually played to near its real end — otherwise a fresh track
    // would get skipped seconds after it started.
    final dur = duration.inSeconds;
    if (dur > 0 && _position.inSeconds < dur - 8) {
      return;
    }
    final finished = current;
    if (finished != null) {
      unawaited(_repo.feedback(track: finished, event: 'completed', playedFraction: 1.0));
    }
    // Advance the server queue and stream whatever comes next.
    try {
      _applySnapshot(await _repo.control('next'));
    } catch (_) {}
  }

  Future<void> _guard(Future<void> Function() body) async {
    _error = null;
    try {
      await body();
      _notConnected = false;
    } on HermesApiException catch (e) {
      _handleApiError(e);
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  void _handleApiError(HermesApiException e) {
    if (e.statusCode == 503 || e.message.toLowerCase().contains('unavailable')) {
      _notConnected = true;
    } else {
      _error = e.message;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final s in _sub) {
      s.cancel();
    }
    _svc.dispose();
    super.dispose();
  }
}
