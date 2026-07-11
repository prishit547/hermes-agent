/// Where an agenda entry came from — drives its accent color and icon.
enum CalendarKind { event, task, alarm }

/// A unified agenda entry. The calendar aggregates three sources: Google
/// Calendar events (via the agent), server-side agent tasks (cron), and
/// on-device alarms.
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    required this.kind,
    this.end,
    this.subtitle,
  });

  final String title;
  final DateTime start;
  final DateTime? end;
  final CalendarKind kind;
  final String? subtitle;

  /// Parse one item from the agent's JSON events array.
  static CalendarEvent? fromAgentJson(Map<String, dynamic> json) {
    final start = DateTime.tryParse((json['start'] ?? '').toString());
    if (start == null) return null;
    return CalendarEvent(
      title: (json['title'] ?? 'Event').toString(),
      start: start.toLocal(),
      end: DateTime.tryParse((json['end'] ?? '').toString())?.toLocal(),
      kind: CalendarKind.event,
      subtitle: (json['location'] as String?)?.trim().isNotEmpty == true
          ? json['location'] as String?
          : null,
    );
  }
}
