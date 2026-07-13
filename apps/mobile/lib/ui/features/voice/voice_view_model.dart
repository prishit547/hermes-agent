import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../data/services/audio_service.dart';
import '../../../data/services/voice_stream_service.dart';
import '../../core/halo_orb.dart';

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
  VoiceViewModel(this._voice, this._audio);

  final VoiceStreamService _voice;
  final AudioService _audio;

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

  HaloState _state = HaloState.idle;
  HaloState get state => _state;

  String _label = 'Connecting…';
  String get label => _label;

  String _transcript = 'Starting hands-free voice…';
  String get transcript => _transcript;

  final StringBuffer _reply = StringBuffer();

  void _set(HaloState s, String label, String transcript) {
    _state = s;
    _label = label;
    _transcript = transcript;
    notifyListeners();
  }

  // -- lifecycle --------------------------------------------------------------

  /// Called when the overlay opens: connect the socket and start listening.
  Future<void> begin() async {
    if (_active) return;
    _active = true;
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
    final now = DateTime.now();
    if (amp.current > _speechOnsetDb) {
      _speechStarted = true;
      _lastLoud = now;
    }
    final elapsed = now.difference(_listenStart);
    if (_speechStarted) {
      if (now.difference(_lastLoud) >= _silenceHang || elapsed >= _maxUtterance) {
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
          if (_active) _startListening();
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
        _set(HaloState.idle, 'Error', message);
        if (_active) {
          Future.delayed(const Duration(seconds: 2), () {
            if (_active) _startListening();
          });
        }
      case VoiceClosed():
        if (_active) {
          _set(HaloState.idle, 'Disconnected', 'Voice stream closed. Tap to retry.');
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
    if (!_active) return;
    if (_turnComplete && !_playing && _ttsQueue.isEmpty) {
      _startListening();
    }
  }

  // -- orb tap ----------------------------------------------------------------

  Future<void> tapOrb() async {
    switch (_state) {
      case HaloState.idle:
        if (!_voice.isConnected) {
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

  /// Called when the overlay closes.
  Future<void> reset() async {
    _active = false;
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
    super.dispose();
  }
}
