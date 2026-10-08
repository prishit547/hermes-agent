/// The CLI's most recently observed rate-limit snapshot
/// (`event: rate_limit.status`, a passive side-channel from real turns — the
/// live in-session indicator). Distinct from [CodeUsage]'s session/week
/// percentages, which come from the free `/usage` poll instead.
class CodeRateLimit {
  const CodeRateLimit({this.status, this.resetsAt, this.rateLimitType, this.isUsingOverage});

  final String? status;
  final double? resetsAt;
  final String? rateLimitType;
  final bool? isUsingOverage;

  bool get isLimited => (status ?? '').toLowerCase() != 'allowed' && status != null;

  factory CodeRateLimit.fromJson(Map<String, dynamic> j) => CodeRateLimit(
        status: j['status'] as String?,
        resetsAt: (j['resets_at'] as num?)?.toDouble(),
        rateLimitType: j['rate_limit_type'] as String?,
        isUsingOverage: j['is_using_overage'] as bool?,
      );
}

/// A past detected reset (limit → available again), for the usage timeline.
class CodeResetEvent {
  const CodeResetEvent({required this.at, this.window});
  final double at;

  /// `session` or `week`.
  final String? window;

  DateTime get atTime => DateTime.fromMillisecondsSinceEpoch((at * 1000).round());

  factory CodeResetEvent.fromJson(Map<String, dynamic> j) => CodeResetEvent(
        at: (j['at'] as num?)?.toDouble() ?? 0,
        window: j['window'] as String?,
      );
}

/// Cumulative Claude Code usage (`GET /api/code/usage`).
///
/// `session_used_pct`/`week_used_pct` and their reset times come from the
/// CLI's free `/usage` command (zero-cost — see the backend manager's
/// `refresh_usage` docstring), polled periodically plus on-demand via
/// [CodeRepository.refreshUsage]. `rateLimit` is a secondary, live-only
/// signal that updates mid-turn.
class CodeUsage {
  const CodeUsage({
    required this.totalCostUsd,
    required this.totalTurns,
    required this.perProjectCostUsd,
    this.sessionUsedPct,
    this.sessionResetsAt,
    this.sessionResetsInSeconds,
    this.weekUsedPct,
    this.weekResetsAt,
    this.weekResetsInSeconds,
    this.checkedAt,
    this.rateLimit,
    this.resetEvents = const [],
  });

  final double totalCostUsd;
  final int totalTurns;
  final Map<String, double> perProjectCostUsd;

  final int? sessionUsedPct;
  final double? sessionResetsAt;
  final double? sessionResetsInSeconds;

  final int? weekUsedPct;
  final double? weekResetsAt;
  final double? weekResetsInSeconds;

  /// When the last `/usage` check ran.
  final double? checkedAt;

  final CodeRateLimit? rateLimit;
  final List<CodeResetEvent> resetEvents;

  bool get hasUsageCheck => sessionUsedPct != null || weekUsedPct != null;

  DateTime? get sessionResetsAtTime => _toDateTime(sessionResetsAt);
  DateTime? get weekResetsAtTime => _toDateTime(weekResetsAt);

  static DateTime? _toDateTime(double? epochSeconds) => epochSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch((epochSeconds * 1000).round());

  factory CodeUsage.fromJson(Map<String, dynamic> j) => CodeUsage(
        totalCostUsd: (j['total_cost_usd'] as num?)?.toDouble() ?? 0,
        totalTurns: (j['total_turns'] as num?)?.toInt() ?? 0,
        perProjectCostUsd: (j['per_project_cost_usd'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        sessionUsedPct: (j['session_used_pct'] as num?)?.toInt(),
        sessionResetsAt: (j['session_resets_at'] as num?)?.toDouble(),
        sessionResetsInSeconds: (j['session_resets_in_seconds'] as num?)?.toDouble(),
        weekUsedPct: (j['week_used_pct'] as num?)?.toInt(),
        weekResetsAt: (j['week_resets_at'] as num?)?.toDouble(),
        weekResetsInSeconds: (j['week_resets_in_seconds'] as num?)?.toDouble(),
        checkedAt: (j['usage_checked_at'] as num?)?.toDouble(),
        rateLimit: j['last_rate_limit'] is Map<String, dynamic>
            ? CodeRateLimit.fromJson(j['last_rate_limit'] as Map<String, dynamic>)
            : null,
        resetEvents: (j['reset_events'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CodeResetEvent.fromJson)
            .toList(),
      );
}
