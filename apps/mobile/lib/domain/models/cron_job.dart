/// A server-side scheduled agent task (`GET/POST /api/jobs`). Runs [prompt] on
/// [scheduleDisplay] and executes on the gateway even when the app is closed.
class CronJob {
  const CronJob({
    required this.id,
    required this.name,
    this.prompt = '',
    this.scheduleDisplay = '',
    this.enabled = true,
    this.state = '',
    this.deliver = 'local',
    this.nextRunAt,
    this.lastRunAt,
    this.lastStatus,
  });

  final String id;
  final String name;
  final String prompt;
  final String scheduleDisplay;
  final bool enabled;
  final String state; // scheduled | paused | running | …
  final String deliver;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final String? lastStatus;

  bool get isPaused => state == 'paused' || !enabled;

  static DateTime? _t(dynamic raw) => raw is String ? DateTime.tryParse(raw) : null;

  factory CronJob.fromJson(Map<String, dynamic> json) {
    final schedule = json['schedule'];
    final display = (json['schedule_display'] as String?) ??
        (schedule is Map ? (schedule['display'] ?? schedule['expr'])?.toString() : null) ??
        '';
    return CronJob(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      prompt: (json['prompt'] as String?) ?? '',
      scheduleDisplay: display,
      enabled: json['enabled'] != false,
      state: (json['state'] as String?) ?? '',
      deliver: (json['deliver'] as String?) ?? 'local',
      nextRunAt: _t(json['next_run_at']),
      lastRunAt: _t(json['last_run_at']),
      lastStatus: json['last_status'] as String?,
    );
  }
}
