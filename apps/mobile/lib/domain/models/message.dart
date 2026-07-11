/// Roles a chat message can take, mirroring the OpenAI chat schema the
/// Hermes `/v1/chat/completions` endpoint expects. [tool] appears in loaded
/// session transcripts (tool call results) and is filtered out of the UI.
enum MessageRole { user, assistant, system, tool }

/// A single conversation turn shown in the UI and sent to the agent.
///
/// [streaming] marks the assistant bubble that is currently being filled in
/// from the SSE token stream; the View uses it to show a caret/indicator.
/// [id] and [timestamp] are populated when a message is loaded from a
/// persisted session (they are null for locally-composed turns).
class Message {
  Message({
    required this.role,
    required this.content,
    this.streaming = false,
    this.id,
    this.timestamp,
    this.toolName,
  });

  final MessageRole role;
  final String content;
  final bool streaming;

  /// Server-assigned message id (present for messages loaded from a session).
  final String? id;

  /// When the message was recorded, if known.
  final DateTime? timestamp;

  /// For tool messages: the tool that produced this entry.
  final String? toolName;

  Message copyWith({String? content, bool? streaming}) => Message(
        role: role,
        content: content ?? this.content,
        streaming: streaming ?? this.streaming,
        id: id,
        timestamp: timestamp,
        toolName: toolName,
      );

  String get roleWireName => switch (role) {
        MessageRole.user => 'user',
        MessageRole.assistant => 'assistant',
        MessageRole.system => 'system',
        MessageRole.tool => 'tool',
      };

  Map<String, dynamic> toApiJson() => {'role': roleWireName, 'content': content};

  /// Build a [Message] from the api_server's `_message_response` shape
  /// (`GET /api/sessions/{id}/messages` and `run.completed` payloads).
  static Message fromApiJson(Map<String, dynamic> json) {
    final role = switch ((json['role'] as String?)?.toLowerCase()) {
      'user' => MessageRole.user,
      'assistant' => MessageRole.assistant,
      'tool' => MessageRole.tool,
      _ => MessageRole.system,
    };
    DateTime? ts;
    final rawTs = json['timestamp'];
    if (rawTs is String) {
      ts = DateTime.tryParse(rawTs);
    } else if (rawTs is num) {
      ts = DateTime.fromMillisecondsSinceEpoch((rawTs * 1000).round(), isUtc: true);
    }
    return Message(
      role: role,
      content: (json['content'] as String?) ?? '',
      id: json['id'] as String?,
      timestamp: ts,
      toolName: json['tool_name'] as String?,
    );
  }

  /// Whether this message should be shown in the chat transcript. Tool results,
  /// empty system rows, and blank content are hidden.
  bool get isDisplayable =>
      (role == MessageRole.user || role == MessageRole.assistant) &&
      content.trim().isNotEmpty;
}
