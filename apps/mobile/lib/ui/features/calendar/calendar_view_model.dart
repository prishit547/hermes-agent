import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/calendar_repository.dart';
import '../../../data/repositories/chat_repository.dart';
import '../../../data/repositories/jobs_repository.dart';
import '../../../data/services/hermes_api_client.dart';
import '../../../data/services/reminder_service.dart';
import '../../../domain/models/calendar_event.dart';
import '../../../domain/models/message.dart';

/// Whether Google Calendar is reachable.
enum GoogleCalState { unknown, connected, notConnected, error }

/// Drives the calendar. Aggregates three sources into one agenda:
/// • On-device alarms ([ReminderService]) — always available.
/// • Server agent tasks ([JobsRepository]) — their next run time.
/// • Google Calendar events — read via the FAST `/api/calendar/events` endpoint
///   ([CalendarRepository]); natural-language *adding* still uses the agent.
///
/// Results are cached (loaded once via [loadIfNeeded]); pull-to-refresh calls
/// [load]. This is why the calendar no longer re-loads on every tab switch.
class CalendarViewModel extends ChangeNotifier {
  CalendarViewModel({
    required CalendarRepository calendarRepository,
    required ChatRepository chatRepository,
    required ReminderService reminderService,
    required JobsRepository jobsRepository,
  })  : _calendar = calendarRepository,
        _chat = chatRepository,
        _reminders = reminderService,
        _jobs = jobsRepository {
    _reminders.addListener(_onRemindersChanged);
  }

  final CalendarRepository _calendar;
  final ChatRepository _chat;
  final ReminderService _reminders;
  final JobsRepository _jobs;

  // A stable, dedicated session so calendar chatter stays out of the main chat.
  final String _sessionId = 'calendar-${const Uuid().v4()}';

  bool _loadedOnce = false;

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

  static const _cacheKey = 'hermes.calendar_cache';

  /// Load once (cached). Tab switches rebuild the screen, so this avoids
  /// re-fetching on every open. Also loads server tasks.
  Future<void> loadIfNeeded() async {
    if (_loadedOnce || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        _events = raw.map((s) {
          try {
            return CalendarEvent.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<CalendarEvent>().toList();
        _loadedOnce = true;
        _loading = false;
        notifyListeners();
      }
    } catch (_) {}

    await load();
    await loadTasks();
  }

  /// Reload everything: local sources immediately, then Google events (fast REST).
  Future<void> load() async {
    _loadedOnce = true;
    _loading = true;
    _error = null;
    notifyListeners();

    final local = _localEvents();
    final nonAlarms = _events.where((e) => e.kind != CalendarKind.alarm).toList();
    _events = [...local, ...nonAlarms]..sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();

    try {
      final googleEvents = await _fetchGoogleEvents();
      _events = [...local, ...googleEvents]..sort((a, b) => a.start.compareTo(b.start));

      // Save to SharedPreferences cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _cacheKey,
        _events.map((e) => jsonEncode(e.toJson())).toList(),
      );
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

  /// Fetch Google Calendar events via the fast structured endpoint (~1s).
  Future<List<CalendarEvent>> _fetchGoogleEvents() async {
    try {
      final events = await _calendar.listEvents(days: 60);
      _google = GoogleCalState.connected;
      return events;
    } on HermesApiException catch (e) {
      if (e.statusCode == 503 || e.message.toLowerCase().contains('not connected')) {
        _google = GoogleCalState.notConnected;
      } else {
        _google = GoogleCalState.error;
      }
      return const [];
    }
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

  void _onRemindersChanged() {
    final nonAlarms = _events.where((e) => e.kind != CalendarKind.alarm).toList();
    final newLocal = _localEvents();
    _events = [...newLocal, ...nonAlarms]..sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
  }

  @override
  void dispose() {
    _reminders.removeListener(_onRemindersChanged);
    super.dispose();
  }
}
