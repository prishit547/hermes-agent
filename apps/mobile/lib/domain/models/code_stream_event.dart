/// Events emitted by a Claude Code turn stream
/// (`POST /api/code/sessions/{id}/message/stream`).
///
/// The gateway normalises the CLI's `stream-json` events into a named-event SSE
/// format (`event: assistant.text` / `data: {...}`). [HermesApiClient.streamCodeTurn]
/// parses those frames into this sealed hierarchy so the UI can switch on type.
sealed class CodeStreamEvent {
  const CodeStreamEvent();
}

/// The CLI session started; carries the Claude Code `session_id`
/// (`event: session.init`).
class CodeSessionInit extends CodeStreamEvent {
  const CodeSessionInit({this.claudeSessionId, this.model, this.permissionMode});
  final String? claudeSessionId;
  final String? model;
  final String? permissionMode;
}

/// A chunk of assistant prose (`event: assistant.text`).
class CodeAssistantText extends CodeStreamEvent {
  const CodeAssistantText(this.text);
  final String text;
}

/// The model is thinking (`event: assistant.thinking`) — content elided server-side.
class CodeThinking extends CodeStreamEvent {
  const CodeThinking();
}

/// Claude Code invoked a tool (`event: tool.started`).
class CodeToolStarted extends CodeStreamEvent {
  const CodeToolStarted({required this.tool, this.toolId, this.input});
  final String tool;
  final String? toolId;

  /// Truncated JSON preview of the tool input (e.g. the file path / command).
  final String? input;
}

/// A tool returned (`event: tool.result`).
class CodeToolResult extends CodeStreamEvent {
  const CodeToolResult({this.toolId, required this.isError, this.preview});
  final String? toolId;
  final bool isError;
  final String? preview;
}

/// A one-line turn summary from the CLI (`event: turn.summary`).
class CodeTurnSummary extends CodeStreamEvent {
  const CodeTurnSummary(this.text);
  final String text;
}

/// A tool permission that was auto-denied (safe mode).
class CodeDenial {
  const CodeDenial({required this.tool, this.input});
  final String tool;
  final String? input;

  factory CodeDenial.fromJson(Map<String, dynamic> j) => CodeDenial(
        tool: (j['tool'] as String?) ?? 'tool',
        input: j['input'] as String?,
      );
}

/// The turn finished (`event: turn.result`) — the CLI's terminal event.
class CodeTurnResult extends CodeStreamEvent {
  const CodeTurnResult({
    required this.isError,
    required this.result,
    this.denials = const [],
    this.costUsd,
  });
  final bool isError;
  final String result;
  final List<CodeDenial> denials;
  final double? costUsd;

  bool get hasDenials => denials.isNotEmpty;
}

/// Claude Code wants to use a gated tool and is waiting for the phone to
/// approve or deny it (`event: permission.request`, approve mode). The turn's
/// SSE stream stays open while the user decides.
class CodePermissionRequest extends CodeStreamEvent {
  const CodePermissionRequest({
    required this.toolUseId,
    required this.tool,
    required this.summary,
    this.input,
  });
  final String toolUseId;
  final String tool;

  /// A short human line, e.g. the shell command or the file being edited.
  final String summary;
  final String? input;
}

/// The model finished planning and presented a plan (`event: plan.ready`,
/// from an ExitPlanMode call in plan mode). The user can approve it to kick off
/// the implementation in Auto/Approve mode.
class CodePlanReady extends CodeStreamEvent {
  const CodePlanReady(this.plan);
  final String plan;
}

/// The CLI reported its current rate-limit status (`event: rate_limit.status`,
/// observed opportunistically at the start of a turn).
class CodeRateLimitStatus extends CodeStreamEvent {
  const CodeRateLimitStatus({this.status, this.resetsAt, this.rateLimitType});
  final String? status;
  final double? resetsAt;
  final String? rateLimitType;
}

/// The gateway reported an error (`event: error`).
class CodeErrored extends CodeStreamEvent {
  const CodeErrored(this.message);
  final String message;
}

/// Terminal frame (`event: done`).
class CodeStreamDone extends CodeStreamEvent {
  const CodeStreamDone();
}
