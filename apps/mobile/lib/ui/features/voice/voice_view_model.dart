import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../data/services/audio_service.dart';
import '../../../data/services/voice_stream_service.dart';
import '../../core/halo_orb.dart';
import 'overlay/overlay_orb_controller.dart';

/// Drives the Halo voice overlay as a **hands-free** loop over the realtime
/// `/v1/voice/stream` WebSocket:
///
///   connect → listen (mic + silence endpointing) → commit → thinking →
///   speaking (streamed sentence-by-sentence TTS) → auto-listen again.
///
/// Tapping the orb interrupts: during speaking it barge-ins (stop + listen),
/// during listening it commits immediately. Streamed TTS + barge-in are what
/// this path adds over the request/response push-to-talk it replaces.
class VoiceViewModel extends ChangeNotifier {
  static const _callChannel = MethodChannel('hermes/callkit');

  // A public `overlay:` argument mapped to the private `_overlay` field; Dart
  // forbids underscore-named parameters, so an initializing formal isn't usable.
  // ignore: prefer_initializing_formals
  VoiceViewModel(this._voice, this._audio, {OverlayOrbController? overlay}) : _overlay = overlay;

  final VoiceStreamService _voice;
  final AudioService _audio;

  /// Android floating-orb overlay (null / no-op elsewhere).
  final OverlayOrbController? _overlay;
  bool _overlayShown = false;

  /// Whether a floating overlay orb is possible on this platform.
  bool get overlayAvailable => _overlay?.isSupported ?? false;

  /// Whether the floating orb is currently showing.
  bool get overlayShown => _overlayShown;

  final String _sessionId = 'voice-${const Uuid().v4()}';

  // Voice-activity endpointing thresholds (dBFS; 0 = loudest).
  static const double _speechOnsetDb = -35;
  static const _silenceHang = Duration(milliseconds: 1200);
  static const _maxUtterance = Duration(seconds: 15);
  static const _preSpeechTimeout = Duration(seconds: 12);

  StreamSubscription<VoiceEvent>? _eventSub;
  StreamSubscription<Amplitude>? _ampSub;

  /// True while the overlay is open — gates the auto-listen loop.
  bool _active = false;

  bool _speechStarted = false;
  DateTime _lastLoud = DateTime.now();
  DateTime _listenStart = DateTime.now();

  final List<VoiceTtsClip> _ttsQueue = [];
  bool _playing = false;
  bool _turnComplete = false;

  /// Microphone is muted by the user while keeping the voice stream alive.
  bool _muted = false;
  bool get muted => _muted;

  /// Current playback output route (speaker / earpiece / bluetooth).
  AudioOutput get audioOutput => _audio.currentOutput;

  HaloState _state = HaloState.idle;
  HaloState get state => _state;

  /// Normalized mic loudness (0..1) while listening, feeding the reactive orb.
  /// Exposed as a [ValueNotifier] so the orb animates off amplitude ticks
  /// (~5 Hz) without rebuilding the whole overlay via [notifyListeners].
  final ValueNotifier<double> level = ValueNotifier(0);

  String _label = 'Connecting…';
  String get label => _label;

  String _transcript = 'Starting hands-free voice…';
  String get transcript => _transcript;

  final StringBuffer _reply = StringBuffer();

  void _set(HaloState s, String label, String transcript) {
    _state = s;
    _label = label;
    _transcript = transcript;
    // The reactive glow only makes sense while the mic is open.
    if (s != HaloState.listening) level.value = 0;
    notifyListeners();
    _pushToOverlay();
  }

  // -- floating orb overlay ---------------------------------------------------

  /// Whether "display over other apps" is already granted (no prompt).
  Future<bool> hasOverlayPermission() async =>
      await _overlay?.hasPermission() ?? false;

  /// Request the "display over other apps" permission (Android only).
  Future<bool> requestOverlayPermission() async =>
      await _overlay?.requestPermission() ?? false;

  /// Show the floating orb and start mirroring live voice state to it. Taps on
  /// the overlay orb are routed back into [tapOrb].
  Future<void> showOverlay() async {
    if (_overlay == null || _overlayShown) return;
    await _overlay.show(onTap: tapOrb);
    _overlayShown = true;
    level.addListener(_pushToOverlay);
    _pushToOverlay();
    notifyListeners();
  }

  /// Tear the floating orb down.
  Future<void> hideOverlay() async {
    if (_overlay == null || !_overlayShown) return;
    level.removeListener(_pushToOverlay);
    _overlayShown = false;
    await _overlay.hide();
    notifyListeners();
  }

  void _pushToOverlay() {
    if (!_overlayShown) return;
    _overlay?.pushState(state: _state, label: _label, amplitude: level.value);
  }

  // -- lifecycle --------------------------------------------------------------

  /// Called when the overlay opens: connect the socket and start listening.
  Future<void> begin() async {
    if (_active) return;
    _active = true;
    unawaited(_callChannel.invokeMethod('startCall'));
    _set(HaloState.thinking, 'Connecting…', 'Starting hands-free voice…');

    if (!await _audio.hasMicPermission()) {
      _set(HaloState.idle, 'Mic needed', 'Grant microphone access to talk.');
      _active = false;
      return;
    }

    _eventSub = _voice.events.listen(_onEvent);
    final ok = await _voice.connect(sessionId: _sessionId);
    if (!ok) {
      _set(HaloState.idle, 'Offline', 'Could not reach the voice server.');
      _active = false;
      return;
    }
    // Ensure the selected output route is active on the OS audio session.
    await _audio.setOutput(_audio.currentOutput);
    await _startListening();
  }

  Future<void> _startListening() async {
    if (!_active) return;
    _reply.clear();
    _turnComplete = false;
    _speechStarted = false;
    _listenStart = DateTime.now();
    _lastLoud = DateTime.now();
    await _audio.start();
    _ampSub?.cancel();
    _ampSub = _audio.amplitude().listen(_onAmplitude);
    _set(HaloState.listening, 'Listening…', 'Speak now.');
  }

  void _onAmplitude(Amplitude amp) {
    if (_state != HaloState.listening) return;
    // Map dBFS (~-60 silence … 0 loudest) → 0..1 for the reactive orb. The
    // orb low-pass smooths this, so the raw per-tick target is fine here.
    level.value = ((amp.current + 60.0) / 60.0).clamp(0.0, 1.0);
    final now = DateTime.now();
    if (amp.current > _speechOnsetDb) {
      _speechStarted = true;
      _lastLoud = now;
    }
    final elapsed = now.difference(_listenStart);
    if (_speechStarted) {
      if (now.difference(_lastLoud) >= _silenceHang ||
          elapsed >= _maxUtterance) {
        _commitUtterance();
      }
    } else if (elapsed >= _preSpeechTimeout) {
      // Heard nothing — stop the mic and idle out of the loop.
      _stopListening();
      _set(HaloState.idle, 'Tap to talk', 'Tap the orb to talk again.');
    }
  }

  Future<void> _stopListening() async {
    await _ampSub?.cancel();
    _ampSub = null;
  }

  Future<void> _commitUtterance() async {
    if (_state != HaloState.listening) return;
    await _stopListening();
    _set(HaloState.thinking, 'Thinking…', 'Transcribing…');
    final bytes = await _audio.stop();
    if (bytes.isEmpty) {
      await _startListening();
      return;
    }
    _voice.sendUtterance(bytes);
  }

  // -- inbound events ---------------------------------------------------------

  void _onEvent(VoiceEvent event) {
    switch (event) {
      case VoiceReady():
        break;
      case VoiceTranscript(:final text):
        if (text.trim().isEmpty) {
          // Nothing recognized — resume listening.
          if (_active && !_muted) _startListening();
        } else {
          _set(HaloState.thinking, 'Thinking…', '“$text”');
        }
      case VoiceDelta(:final text):
        _reply.write(text);
        _set(HaloState.speaking, 'Speaking', _reply.toString().trim());
      case VoiceTtsClip():
        _ttsQueue.add(event);
        _drainTts();
      case VoiceTurnComplete():
        _turnComplete = true;
        _maybeAdvance();
      case VoiceError(:final message):
        _set(HaloState.error, 'Error', message);
        if (_active && !_muted) {
          Future.delayed(const Duration(seconds: 2), () {
            if (_active && !_muted) _startListening();
          });
        }
      case VoiceClosed():
        if (_active) {
          _set(
            HaloState.idle,
            'Disconnected',
            'Voice stream closed. Tap to retry.',
          );
        }
    }
  }

  Future<void> _drainTts() async {
    if (_playing) return;
    _playing = true;
    while (_ttsQueue.isNotEmpty) {
      final clip = _ttsQueue.removeAt(0);
      try {
        await _audio.playToCompletion(clip.bytes, mimeType: clip.mime);
      } catch (_) {
        // Best-effort playback; skip a bad clip.
      }
    }
    _playing = false;
    _maybeAdvance();
  }

  /// Once the turn is complete AND all queued TTS has played, loop back to
  /// listening (hands-free).
  void _maybeAdvance() {
    if (!_active || _muted) return;
    if (_turnComplete && !_playing && _ttsQueue.isEmpty) {
      _startListening();
    }
  }

  // -- orb tap ----------------------------------------------------------------

  Future<void> tapOrb() async {
    switch (_state) {
      case HaloState.idle:
      case HaloState.error:
        if (_muted) {
          await toggleMute();
        } else if (!_voice.isConnected) {
          _active = false;
          await begin();
        } else {
          await _startListening();
        }
      case HaloState.listening:
        // Manual endpoint — send what we have if the user spoke.
        if (_speechStarted) {
          await _commitUtterance();
        }
      case HaloState.speaking:
        // Barge-in: interrupt the reply and listen again.
        _voice.bargeIn();
        _ttsQueue.clear();
        await _audio.stopPlayback();
        _turnComplete = false;
        await _startListening();
      case HaloState.thinking:
        break; // busy
    }
  }

  // -- in-call controls -------------------------------------------------------

  /// Toggle microphone mute without tearing down the realtime stream.
  Future<void> toggleMute() async {
    if (_muted) {
      _muted = false;
      notifyListeners();
      if (!_active) return;
      if (_state == HaloState.speaking) {
        _voice.bargeIn();
        _ttsQueue.clear();
        await _audio.stopPlayback();
        _turnComplete = false;
      }
      if (_state == HaloState.idle || _state == HaloState.speaking) {
        await _startListening();
      }
    } else {
      _muted = true;
      notifyListeners();
      await _stopListening();
      await _audio.cancel();
      _set(HaloState.idle, 'Muted', 'Microphone is muted.');
    }
  }

  /// Cycle the audio output route (speaker → earpiece → bluetooth when paired).
  Future<void> cycleAudioOutput() async {
    final routes = await _audio.availableOutputs();
    if (routes.isEmpty) return;
    final idx = routes.indexOf(_audio.currentOutput);
    final next = routes[(idx + 1) % routes.length];
    await _audio.setOutput(next);
    notifyListeners();
  }

  /// Called when the overlay closes.
  Future<void> reset() async {
    unawaited(_callChannel.invokeMethod('endCall'));
    await hideOverlay();
    _active = false;
    _muted = false;
    await _stopListening();
    await _audio.cancel();
    await _audio.stopPlayback();
    _ttsQueue.clear();
    _playing = false;
    _voice.cancel();
    await _voice.close();
    await _eventSub?.cancel();
    _eventSub = null;
    _set(HaloState.idle, 'Tap to talk', 'Tap the orb to talk hands-free.');
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _eventSub?.cancel();
    level.removeListener(_pushToOverlay);
    level.dispose();
    super.dispose();
  }
}
