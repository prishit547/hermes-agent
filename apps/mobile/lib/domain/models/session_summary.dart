/// A row from `GET /api/sessions` — one persisted Hermes conversation.
///
/// Sessions live in the shared `~/.hermes/state.db`, so this list spans every
/// client that talks to the same gateway: the mobile app (`source ==
/// "api_server"`), the CLI, cron jobs, and chat platforms. [source] is the
/// device/channel a conversation originated from.
class SessionSummary {
  const SessionSummary({
    required this.id,
    this.title,
    this.source = '',
    this.preview,
    this.model,
    this.messageCount = 0,
    this.lastActive,
    this.parentSessionId,
  });

  final String id;
  final String? title;
  final String source;
  final String? preview;
  final String? model;
  final int messageCount;
  final DateTime? lastActive;
  final String? parentSessionId;

  /// A human label for the row: explicit title, else the preview, else the id.
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final p = preview?.trim();
    if (p != null && p.isNotEmpty) return p.length > 60 ? '${p.substring(0, 60)}…' : p;
    return id;
  }

  /// True for conversations started from this mobile app.
  bool get isThisApp => source == 'api_server';

  static DateTime? _parseTime(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch((raw * 1000).round(), isUtc: true);
    }
    return null;
  }

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        id: (json['id'] ?? '').toString(),
        title: json['title'] as String?,
        source: (json['source'] as String?) ?? '',
        preview: json['preview'] as String?,
        model: json['model'] as String?,
        messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
        lastActive: _parseTime(json['last_active']),
        parentSessionId: json['parent_session_id'] as String?,
      );
}
