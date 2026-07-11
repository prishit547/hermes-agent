import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/chat_repository.dart';
import '../../../../data/repositories/session_repository.dart';
import '../../../../data/services/audio_service.dart';
import '../../../../data/services/hermes_api_client.dart';
import '../../../../domain/models/chat_stream_event.dart';
import '../../../../domain/models/message.dart';
import '../../../../domain/models/session_summary.dart';

/// Drives the chat screen: owns the *current* conversation (a durable
/// server-side session), streams assistant replies via the session chat
/// endpoint, and supports the full session lifecycle — new, switch, rename,
/// delete, fork. History lives in `~/.hermes/state.db`, so switching sessions
/// reloads the real transcript and conversations persist across app restarts.
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required ChatRepository chatRepository,
    required SessionRepository sessionRepository,
    required AudioService audioService,
  })  : _chat = chatRepository,
        _sessions = sessionRepository,
        _audio = audioService;

  final ChatRepository _chat;
  final SessionRepository _sessions;
  final AudioService _audio;

  /// The conversation currently open, or null before the first turn / after a
  /// fresh "new chat". A session is created lazily on the first send.
  SessionSummary? _current;
  SessionSummary? get current => _current;
  String? get currentSessionId => _current?.id;
  String get title => _current?.displayTitle ?? 'New chat';

  final List<Message> _messages = [];
  List<Message> get messages => List.unmodifiable(_messages);

  bool _isSending = false;
  bool get isSending => _isSending;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isTranscribing = false;
  bool get isTranscribing => _isTranscribing;

  bool _loadingHistory = false;
  bool get loadingHistory => _loadingHistory;

  /// Transient status line shown while a tool is running (empty when idle).
  String _toolStatus = '';
  String get toolStatus => _toolStatus;

  /// The active stream subscription — cancelling it (via [stop]) disconnects
  /// the SSE stream, which the server treats as an interrupt for that turn.
  StreamSubscription<ChatStreamEvent>? _streamSub;

  /// When true, assistant replies are spoken aloud via TTS after streaming.
  bool _autoSpeak = false;
  bool get autoSpeak => _autoSpeak;
  void toggleAutoSpeak() {
    _autoSpeak = !_autoSpeak;
    notifyListeners();
  }

  String? _error;
  String? get error => _error;
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  /// Start a fresh conversation. The server-side session is created lazily on
  /// the next send, so this just clears the current view.
  void newChat() {
    _stopStream();
    _current = null;
    _messages.clear();
    _toolStatus = '';
    _error = null;
    _isSending = false;
    notifyListeners();
  }

  /// Open an existing conversation and load its transcript.
  Future<void> switchTo(SessionSummary session) async {
    _stopStream();
    _current = session;
    _messages.clear();
    _toolStatus = '';
    _error = null;
    _loadingHistory = true;
    notifyListeners();
    try {
      final history = await _sessions.history(session.id);
      _messages
        ..clear()
        ..addAll(history.where((m) => m.isDisplayable));
    } catch (e) {
      _error = 'Could not load conversation: $e';
    } finally {
      _loadingHistory = false;
      notifyListeners();
    }
  }

  /// Rename the current conversation.
  Future<void> rename(String title) async {
    final id = _current?.id;
    if (id == null) return;
    try {
      _current = await _sessions.rename(id, title);
      notifyListeners();
    } catch (e) {
      _error = 'Rename failed: $e';
      notifyListeners();
    }
  }

  /// Delete the current conversation and reset to a fresh chat.
  Future<void> deleteCurrent() async {
    final id = _current?.id;
    if (id == null) return;
    try {
      await _sessions.delete(id);
    } catch (e) {
      _error = 'Delete failed: $e';
      notifyListeners();
      return;
    }
    newChat();
  }

  /// Delete an arbitrary session (from the drawer). Resets the view if it was
  /// the one currently open.
  Future<void> deleteSession(String id) async {
    try {
      await _sessions.delete(id);
      if (_current?.id == id) newChat();
    } catch (e) {
      _error = 'Delete failed: $e';
      notifyListeners();
    }
  }

  /// Branch the current conversation and switch to the new child.
  Future<void> fork() async {
    final id = _current?.id;
    if (id == null) return;
    try {
      final child = await _sessions.fork(id);
      await switchTo(child);
    } catch (e) {
      _error = 'Branch failed: $e';
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Turns
  // ---------------------------------------------------------------------------

  /// Send [text] as a user turn and stream the assistant's reply into a live
  /// bubble. Creates a session first if none is open.
  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;

    _error = null;

    // Ensure a durable session exists for this turn.
    if (_current == null) {
      try {
        _current = await _sessions.create();
      } catch (e) {
        _error = 'Could not start conversation: $e';
        notifyListeners();
        return;
      }
    }
    final sessionId = _current!.id;

    _messages.add(Message(role: MessageRole.user, content: trimmed));
    final assistantIndex = _messages.length;
    _messages.add(Message(role: MessageRole.assistant, content: '', streaming: true));
    _isSending = true;
    _toolStatus = '';
    notifyListeners();

    final buffer = StringBuffer();
    final completer = Completer<void>();

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    _streamSub = _sessions
        .streamTurn(sessionId: sessionId, message: trimmed)
        .listen(
      (event) {
        switch (event) {
          case ChatDelta(:final text):
            buffer.write(text);
            _messages[assistantIndex] =
                _messages[assistantIndex].copyWith(content: buffer.toString());
            _toolStatus = '';
            notifyListeners();
          case ChatToolEvent(:final phase, :final toolName):
            _toolStatus = phase == 'started' ? 'Running $toolName…' : '';
            notifyListeners();
          case ChatThinking():
            _toolStatus = 'Thinking…';
            notifyListeners();
          case ChatCompleted(:final content):
            if (content.isNotEmpty) {
              buffer
                ..clear()
                ..write(content);
              _messages[assistantIndex] =
                  _messages[assistantIndex].copyWith(content: content);
            }
          case ChatErrored(:final message):
            _error = message;
          case ChatRunCompleted():
          case ChatDone():
            break;
        }
      },
      onError: (Object e) {
        _error = e is HermesApiException ? e.message : 'Could not reach Hermes: $e';
        finish();
      },
      onDone: finish,
      cancelOnError: true,
    );

    await completer.future;
    _streamSub = null;
    _messages[assistantIndex] =
        _messages[assistantIndex].copyWith(content: buffer.toString(), streaming: false);
    _isSending = false;
    _toolStatus = '';
    notifyListeners();

    if (_autoSpeak && buffer.isNotEmpty && _error == null) {
      await _speak(buffer.toString());
    }
  }

  /// Cancel the in-flight turn (the `/stop` command). Disconnecting the SSE
  /// stream interrupts the agent server-side.
  void stop() {
    _stopStream();
    if (_isSending) {
      _isSending = false;
      _toolStatus = '';
      notifyListeners();
    }
  }

  void _stopStream() {
    _streamSub?.cancel();
    _streamSub = null;
  }

  // ---------------------------------------------------------------------------
  // Push-to-talk (mic in the chat input)
  // ---------------------------------------------------------------------------

  Future<void> startRecording() async {
    if (_isRecording || _isSending) return;
    if (!await _audio.hasMicPermission()) {
      _error = 'Microphone permission denied';
      notifyListeners();
      return;
    }
    await _audio.start();
    _isRecording = true;
    notifyListeners();
  }

  Future<void> stopRecordingAndSend() async {
    if (!_isRecording) return;
    _isRecording = false;
    _isTranscribing = true;
    notifyListeners();

    try {
      final bytes = await _audio.stop();
      if (bytes.isEmpty) {
        _isTranscribing = false;
        notifyListeners();
        return;
      }
      final transcript = await _chat.transcribe(
        bytes,
        AudioService.recordingMimeType,
        AudioService.recordingFilename,
      );
      _isTranscribing = false;
      notifyListeners();
      if (transcript.isNotEmpty) {
        await sendText(transcript);
      }
    } catch (e) {
      _error = 'Transcription failed: $e';
      _isTranscribing = false;
      notifyListeners();
    }
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    await _audio.cancel();
    _isRecording = false;
    notifyListeners();
  }

  Future<void> _speak(String text) async {
    try {
      final audio = await _chat.synthesize(text);
      if (audio.isNotEmpty) await _audio.play(audio);
    } catch (_) {
      // TTS is best-effort; a synthesis failure shouldn't surface as a chat
      // error since the text reply already landed.
    }
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }
}
