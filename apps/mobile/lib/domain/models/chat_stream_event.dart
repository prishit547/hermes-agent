import 'message.dart';

/// Events emitted by the session chat stream (`POST /api/sessions/{id}/chat/stream`).
///
/// The endpoint uses a named-event SSE format (`event: assistant.delta` /
/// `data: {...}`) — distinct from the OpenAI chunk format of
/// `/v1/chat/completions`. [HermesApiClient.streamSessionChat] parses those
/// frames into this sealed hierarchy so the ViewModel can switch on type.
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// An incremental chunk of assistant text (`event: assistant.delta`).
class ChatDelta extends ChatStreamEvent {
  const ChatDelta(this.text);
  final String text;
}

/// A tool began or finished running (`event: tool.started|tool.completed|tool.failed`).
class ChatToolEvent extends ChatStreamEvent {
  const ChatToolEvent({required this.phase, required this.toolName, this.preview});

  /// One of `started`, `completed`, `failed`.
  final String phase;
  final String toolName;
  final String? preview;

  bool get isRunning => phase == 'started';
}

/// A reasoning/thinking progress chunk (`event: tool.progress`, tool `_thinking`).
class ChatThinking extends ChatStreamEvent {
  const ChatThinking(this.text);
  final String text;
}

/// The assistant turn finished; carries the full final text (`event: assistant.completed`).
class ChatCompleted extends ChatStreamEvent {
  const ChatCompleted(this.content);
  final String content;
}

/// The whole run finished; carries the canonical turn transcript (`event: run.completed`).
class ChatRunCompleted extends ChatStreamEvent {
  const ChatRunCompleted({required this.messages, this.usage});
  final List<Message> messages;
  final Map<String, dynamic>? usage;
}

/// The server reported an error mid-stream (`event: error`).
class ChatErrored extends ChatStreamEvent {
  const ChatErrored(this.message);
  final String message;
}

/// Terminal frame (`event: done`).
class ChatDone extends ChatStreamEvent {
  const ChatDone();
}
