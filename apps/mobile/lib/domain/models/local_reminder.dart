/// An on-device alarm/reminder scheduled with the local notifications plugin.
/// Fires at [time] on the device even with no network; [repeatDaily] repeats it
/// every day at the same clock time.
class LocalReminder {
  const LocalReminder({
    required this.id,
    required this.title,
    required this.time,
    this.repeatDaily = false,
  });

  /// Stable notification id (also used to cancel/reschedule).
  final int id;
  final String title;
  final DateTime time;
  final bool repeatDaily;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'time': time.toIso8601String(),
        'repeatDaily': repeatDaily,
      };

  factory LocalReminder.fromJson(Map<String, dynamic> json) => LocalReminder(
        id: (json['id'] as num).toInt(),
        title: (json['title'] ?? '').toString(),
        time: DateTime.tryParse((json['time'] ?? '').toString()) ?? DateTime.now(),
        repeatDaily: json['repeatDaily'] == true,
      );
}
