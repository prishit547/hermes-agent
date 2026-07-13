import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/chat_repository.dart';
import '../../../data/services/reminder_service.dart';
import '../../../domain/models/calendar_event.dart';
import '../../../domain/models/local_reminder.dart';
import '../../../domain/models/message.dart';

enum TodayTimePeriod { morningRise, deepWork, windDown }

/// Backs the Today dashboard with real data: a live agent-generated briefing
/// plus today's calendar events (one combined agent round-trip), and today's
/// on-device reminders as the "Due today" list.
class TodayViewModel extends ChangeNotifier {
  TodayViewModel({
    required ChatRepository chatRepository,
    required ReminderService reminderService,
  })  : _chat = chatRepository,
        _reminders = reminderService {
    _reminders.addListener(notifyListeners);
  }

  final ChatRepository _chat;
  final ReminderService _reminders;

  final String _sessionId = 'today-${const Uuid().v4()}';

  bool _loading = false;
  bool get loading => _loading;

  bool _loadedOnce = false;

  String _briefing = '';
  String get briefing => _briefing;

  List<CalendarEvent> _events = [];

  /// Upcoming events today (start in the future or within the last hour),
  /// soonest first, capped for the dashboard.
  List<CalendarEvent> get upNext {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final upcoming = _events
        .where((e) =>
            e.start.isBefore(tomorrow) &&
            e.start.isAfter(now.subtract(const Duration(hours: 1))))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return upcoming.take(3).toList();
  }

  /// Reminders (alarms) due today, soonest first.
  List<LocalReminder> get dueToday {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return _reminders.reminders
        .where((r) => r.time.isBefore(tomorrow))
        .toList();
  }

  /// Relative time to the next upcoming event ("in 3h 20m"), or null.
  String? get nextInLabel {
    final list = upNext;
    if (list.isEmpty) return null;
    final diff = list.first.start.difference(DateTime.now());
    if (diff.isNegative) return 'now';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return 'in ${h}h ${m}m';
    return 'in ${m}m';
  }

  static const _briefingCacheKey = 'hermes.today.briefing_cache';
  static const _eventsCacheKey = 'hermes.today.events_cache';

  TodayTimePeriod _getCurrentPeriod() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) {
      return TodayTimePeriod.morningRise;
    } else if (hour >= 12 && hour < 18) {
      return TodayTimePeriod.deepWork;
    } else {
      return TodayTimePeriod.windDown;
    }
  }

  /// Load once (on first Today open); no-op if already loaded or loading. Tab
  /// switches rebuild the screen, so this avoids re-firing the ~20s agent call.
  Future<void> loadIfNeeded({TodayTimePeriod? period}) async {
    if (_loadedOnce || _loading) return;
    _loading = true;
    notifyListeners();
    final currentPeriod = period ?? _getCurrentPeriod();
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedBriefing = prefs.getString('${_briefingCacheKey}_${currentPeriod.name}');
      final cachedEvents = prefs.getStringList(_eventsCacheKey);
      if (cachedBriefing != null) {
        _briefing = cachedBriefing;
        if (cachedEvents != null) {
          _events = cachedEvents.map((s) {
            try {
              return CalendarEvent.fromJson(jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          }).whereType<CalendarEvent>().toList();
        }
        _loadedOnce = true;
        _loading = false;
        notifyListeners();
        return;
      }
    } catch (_) {}

    await load(period: currentPeriod);
  }

  Future<void> load({TodayTimePeriod? period}) async {
    _loading = true;
    _loadedOnce = true;
    notifyListeners();

    final currentPeriod = period ?? _getCurrentPeriod();

    final contextPrompt = switch (currentPeriod) {
      TodayTimePeriod.morningRise =>
        'Write a warm, concise 2-sentence morning briefing for today, welcoming the day, listing today\'s calendar events, and mentioning how busy today is. ',
      TodayTimePeriod.deepWork =>
        'Write a warm, concise 2-sentence afternoon briefing, focusing on focus, productivity, task priorities, and listing today\'s remaining calendar events. ',
      TodayTimePeriod.windDown =>
        'Write a warm, concise 2-sentence evening wind-down briefing, focusing on reviewing today, relaxation, preparing for tomorrow, and listing tomorrow\'s calendar events. ',
    };

    final prompt =
        '$contextPrompt Use the google_calendar tool for events. '
        'Respond with ONLY a compact JSON object, no prose, no code fences, of the form '
        '{"briefing": str, "events": [{"title": str, "start": ISO8601, "end": ISO8601 or null, "location": str or null}]}. '
        'If Google Calendar is not connected, still return a friendly briefing and an empty events array.';

    final buffer = StringBuffer();
    try {
      await for (final delta in _chat.streamReply(
        history: [Message(role: MessageRole.user, content: prompt)],
        sessionId: _sessionId,
      )) {
        buffer.write(delta);
      }
      final obj = _extractJsonObject(buffer.toString());
      if (obj != null) {
        _briefing = (obj['briefing'] as String?)?.trim() ?? '';
        _events = (obj['events'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CalendarEvent.fromAgentJson)
            .whereType<CalendarEvent>()
            .toList();

        // Save to cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('${_briefingCacheKey}_${currentPeriod.name}', _briefing);
        await prefs.setStringList(
          _eventsCacheKey,
          _events.map((e) => jsonEncode(e.toJson())).toList(),
        );
      } else {
        // Fall back to the raw text as the briefing if JSON parsing fails.
        final text = buffer.toString().trim();
        if (text.isNotEmpty) _briefing = text.length > 240 ? '${text.substring(0, 240)}…' : text;
      }
    } catch (e) {
      _briefing = '';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start == -1) return null;
    var depth = 0;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          try {
            return jsonDecode(text.substring(start, i + 1)) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _reminders.removeListener(notifyListeners);
    super.dispose();
  }
}
