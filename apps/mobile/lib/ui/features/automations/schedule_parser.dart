/// A cron expression plus a human-friendly description of when it fires.
class ParsedSchedule {
  const ParsedSchedule(this.cron, this.display);

  final String cron; // "minute hour dom month dow"
  final String display;
}

/// Best-effort natural-language → cron for the common phrasings people use when
/// describing a routine ("every morning at 8", "weekdays at 9pm", "every hour").
///
/// Returns null when the phrase can't be confidently mapped, so the caller can
/// fall back to preset chips rather than guessing.
ParsedSchedule? parseSchedule(String input) {
  final s = input.trim().toLowerCase();
  if (s.isEmpty) return null;

  // --- interval phrases ("every N ...") --------------------------------------
  if (RegExp(r'\bevery\s+minute\b').hasMatch(s)) {
    return const ParsedSchedule('* * * * *', 'Every minute');
  }
  if (RegExp(r'\b(half[\s-]?hour|every\s+30\s+min)').hasMatch(s)) {
    return const ParsedSchedule('*/30 * * * *', 'Every 30 minutes');
  }
  final everyMin = RegExp(r'\bevery\s+(\d+)\s+min').firstMatch(s);
  if (everyMin != null) {
    final n = int.parse(everyMin.group(1)!);
    if (n >= 1 && n <= 59) {
      return ParsedSchedule('*/$n * * * *', 'Every $n minutes');
    }
  }
  if (RegExp(r'\b(hourly|every\s+hour)\b').hasMatch(s)) {
    return const ParsedSchedule('0 * * * *', 'Every hour');
  }
  final everyHour = RegExp(r'\bevery\s+(\d+)\s+hour').firstMatch(s);
  if (everyHour != null) {
    final n = int.parse(everyHour.group(1)!);
    if (n >= 1 && n <= 23) {
      return ParsedSchedule('0 */$n * * *', 'Every $n hours');
    }
  }

  // --- time-of-day + day-of-week ---------------------------------------------
  final time = _parseTime(s);
  if (time == null) return null; // nothing anchoring a daily-style schedule
  final (hour, minute) = time;

  final dow = _parseDayOfWeek(s);
  final cron = '$minute $hour * * ${dow?.cron ?? '*'}';
  final when = _formatTime(hour, minute);
  final display = dow == null ? 'Daily at $when' : '${dow.label} at $when';
  return ParsedSchedule(cron, display);
}

/// Extracts an (hour, minute) 24h pair from phrases like "8", "8am", "8:30",
/// "9 pm", "21:00", "noon", "midnight", "morning", "evening".
(int, int)? _parseTime(String s) {
  if (RegExp(r'\bnoon\b').hasMatch(s)) return (12, 0);
  if (RegExp(r'\bmidnight\b').hasMatch(s)) return (0, 0);

  // Explicit clock time, optional am/pm: "8", "8:30", "8am", "8:30 pm", "21:00".
  final m = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b').firstMatch(s);
  if (m != null) {
    var hour = int.parse(m.group(1)!);
    final minute = m.group(2) != null ? int.parse(m.group(2)!) : 0;
    final ampm = m.group(3);
    if (minute > 59) return null;
    if (ampm == 'pm' && hour < 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;
    // Bare number without am/pm and above 23 is not a valid hour.
    if (hour > 23) return null;
    return (hour, minute);
  }

  // Named periods of day.
  if (RegExp(r'\bmorning\b').hasMatch(s)) return (8, 0);
  if (RegExp(r'\bafternoon\b').hasMatch(s)) return (15, 0);
  if (RegExp(r'\bevening\b').hasMatch(s)) return (18, 0);
  if (RegExp(r'\bnight\b').hasMatch(s)) return (21, 0);
  return null;
}

class _Dow {
  const _Dow(this.cron, this.label);
  final String cron;
  final String label;
}

_Dow? _parseDayOfWeek(String s) {
  if (RegExp(r'\bweekday').hasMatch(s)) return const _Dow('1-5', 'Weekdays');
  if (RegExp(r'\bweekend').hasMatch(s)) return const _Dow('0,6', 'Weekends');

  const days = [
    ('sunday', 'sun', 0, 'Sundays'),
    ('monday', 'mon', 1, 'Mondays'),
    ('tuesday', 'tue', 2, 'Tuesdays'),
    ('wednesday', 'wed', 3, 'Wednesdays'),
    ('thursday', 'thu', 4, 'Thursdays'),
    ('friday', 'fri', 5, 'Fridays'),
    ('saturday', 'sat', 6, 'Saturdays'),
  ];
  for (final (full, abbr, num, label) in days) {
    if (RegExp('\\b($full|$abbr)s?\\b').hasMatch(s)) {
      return _Dow('$num', label);
    }
  }
  return null;
}

String _formatTime(int hour, int minute) {
  final period = hour < 12 ? 'AM' : 'PM';
  var h = hour % 12;
  if (h == 0) h = 12;
  final mm = minute.toString().padLeft(2, '0');
  return '$h:$mm $period';
}
