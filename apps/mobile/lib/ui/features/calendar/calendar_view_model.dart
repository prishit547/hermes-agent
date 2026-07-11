import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/chat_repository.dart';
import '../../../data/repositories/jobs_repository.dart';
import '../../../data/services/reminder_service.dart';
import '../../../domain/models/calendar_event.dart';
import '../../../domain/models/message.dart';

/// Whether Google Calendar is reachable through the agent.
enum GoogleCalState { unknown, connected, notConnected, error }

/// Drives the calendar. Aggregates three sources into one agenda:
/// • On-device alarms ([ReminderService]) — always available.
/// • Server agent tasks ([JobsRepository]) — their next run time.
/// • Google Calendar events — fetched by asking the agent (which calls the
///   `google_calendar` tool). Per the chosen design, the calendar is driven
///   through the agent rather than a dedicated REST endpoint.
class CalendarViewModel extends ChangeNotifier {
  CalendarViewModel({
    required ChatRepository chatRepository,
    required ReminderService reminderService,
    required JobsRepository jobsRepository,
  })  : _chat = chatRepository,
        _reminders = reminderService,
        _jobs = jobsRepository;

  final ChatRepository _chat;
  final ReminderService _reminders;
  final JobsRepository _jobs;

  // A stable, dedicated session so calendar chatter stays out of the main chat.
  final String _sessionId = 'calendar-${const Uuid().v4()}';

  bool _loading = false;
  bool get loading => _loading;

  GoogleCalState _google = GoogleCalState.unknown;
  GoogleCalState get googleState => _google;

  String? _error;
  String? get error => _error;

  List<CalendarEvent> _events = [];
  List<CalendarEvent> get events => List.unmodifiable(_events);

  /// Events grouped by calendar day, ordered soonest-first.
  Map<DateTime, List<CalendarEvent>> get byDay {
    final map = <DateTime, List<CalendarEvent>>{};
    for (final e in _events) {
      final day = DateTime(e.start.year, e.start.month, e.start.day);
      map.putIfAbsent(day, () => []).add(e);
    }
    final sortedKeys = map.keys.toList()..sort();
    return {for (final k in sortedKeys) k: (map[k]!..sort((a, b) => a.start.compareTo(b.start)))};
  }

  /// Reload everything: local sources immediately, then Google via the agent.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    final local = _localEvents();
    _events = [...local];
    notifyListeners();

    try {
      final googleEvents = await _fetchGoogleEvents();
      _events = [...local, ...googleEvents]..sort((a, b) => a.start.compareTo(b.start));
    } catch (e) {
      _error = 'Calendar sync failed: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Local, always-available agenda entries (alarms + upcoming agent tasks).
  List<CalendarEvent> _localEvents() {
    final now = DateTime.now();
    final out = <CalendarEvent>[];
    for (final r in _reminders.reminders) {
      out.add(CalendarEvent(
        title: r.title,
        start: r.time,
        kind: CalendarKind.alarm,
        subtitle: r.repeatDaily ? 'Daily alarm' : 'Alarm',
      ));
    }
    return out.where((e) => e.start.isAfter(now.subtract(const Duration(hours: 1)))).toList();
  }

  /// Load upcoming server agent tasks and fold them into the agenda.
  Future<void> loadTasks() async {
    try {
      final jobs = await _jobs.list();
      final taskEvents = jobs
          .where((j) => j.nextRunAt != null && !j.isPaused)
          .map((j) => CalendarEvent(
                title: j.name,
                start: j.nextRunAt!.toLocal(),
                kind: CalendarKind.task,
                subtitle: 'Agent task',
              ))
          .toList();
      _events = [..._events, ...taskEvents]..sort((a, b) => a.start.compareTo(b.start));
      notifyListeners();
    } catch (_) {
      // Tasks are supplementary; ignore load failures here.
    }
  }

  /// Ask the agent to enumerate Google Calendar events as JSON we can parse.
  Future<List<CalendarEvent>> _fetchGoogleEvents() async {
    const prompt =
        'Using the google_calendar tool, list my calendar events from now through the next 14 days. '
        'Respond with ONLY a compact JSON object, no prose, no code fences, of the form '
        '{"connected": true, "events": [{"title": str, "start": ISO8601, "end": ISO8601 or null, "location": str or null}]}. '
        'If Google Calendar is not connected or not authorized, respond with exactly {"connected": false}.';

    final buffer = StringBuffer();
    await for (final delta in _chat.streamReply(
      history: [Message(role: MessageRole.user, content: prompt)],
      sessionId: _sessionId,
    )) {
      buffer.write(delta);
    }
    final obj = _extractJsonObject(buffer.toString());
    if (obj == null) {
      _google = GoogleCalState.notConnected;
      return const [];
    }
    if (obj['connected'] == false) {
      _google = GoogleCalState.notConnected;
      return const [];
    }
    final rawEvents = (obj['events'] as List<dynamic>? ?? const []);
    final events = rawEvents
        .whereType<Map<String, dynamic>>()
        .map(CalendarEvent.fromAgentJson)
        .whereType<CalendarEvent>()
        .toList();
    _google = GoogleCalState.connected;
    return events;
  }

  /// Create an event from natural language by sending it to the agent, then
  /// refresh the agenda.
  Future<bool> addNatural(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    try {
      final buffer = StringBuffer();
      await for (final delta in _chat.streamReply(
        history: [
          Message(
            role: MessageRole.user,
            content: 'Add this to my Google Calendar using the google_calendar tool: "$trimmed". '
                'Confirm briefly when done.',
          ),
        ],
        sessionId: _sessionId,
      )) {
        buffer.write(delta);
      }
      await load();
      return true;
    } catch (e) {
      _error = 'Could not add event: $e';
      notifyListeners();
      return false;
    }
  }

  /// Extract the first balanced `{...}` JSON object from arbitrary agent text
  /// (handles code fences and surrounding prose).
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
}
