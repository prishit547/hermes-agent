/// A Claude Code conversation bound to one whitelisted project
/// (`/api/code/sessions`). Mirrors the server-side `Session` dataclass.
///
/// [permissionMode] governs what the CLI may do:
///  - `plan` / `default` — reads & investigates, but edits are auto-denied (safe).
///  - `acceptEdits` — edits land in the working tree (reversible via git);
///    nothing leaves the machine until an explicit, phone-approved commit/push.
class CodeSession {
  const CodeSession({
    required this.id,
    required this.project,
    required this.cwd,
    required this.permissionMode,
    required this.title,
    required this.status,
    required this.turns,
    this.claudeSessionId,
    this.lastResult = '',
  });

  final String id;
  final String project;
  final String cwd;
  final String permissionMode;
  final String title;

  /// `idle` | `running` | `error`.
  final String status;
  final int turns;
  final String? claudeSessionId;
  final String lastResult;

  bool get isRunning => status == 'running';
  bool get hasStarted => (claudeSessionId ?? '').isNotEmpty;

  factory CodeSession.fromJson(Map<String, dynamic> json) => CodeSession(
        id: (json['id'] as String?) ?? '',
        project: (json['project'] as String?) ?? '',
        cwd: (json['cwd'] as String?) ?? '',
        permissionMode: (json['permission_mode'] as String?) ?? 'default',
        title: (json['title'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'idle',
        turns: (json['turns'] as num?)?.toInt() ?? 0,
        claudeSessionId: json['claude_session_id'] as String?,
        lastResult: (json['last_result'] as String?) ?? '',
      );
}
