import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/repositories/email_repository.dart';
import '../../../data/services/hermes_api_client.dart';
import '../../../domain/models/email_message.dart';

/// Backs the email surfaces.
///
/// Caching model: the inbox is fetched **once** as a single set (read + unread)
/// and the All / Unread / Read tabs + the search box are filtered **locally** —
/// the gateway only distinguishes UNSEEN vs ALL and ignores search text anyway,
/// so there is nothing to gain from refetching per tab or per keystroke. A short
/// TTL keeps [loadIfNeeded] from hitting the network on every Inbox visit, and a
/// minimum refetch interval throttles notification-driven reloads. Sent mail is
/// a separate folder fetched lazily when its tab is first opened.
class EmailViewModel extends ChangeNotifier {
  EmailViewModel(this._repo);

  final EmailRepository _repo;

  // Tab indices — must match _Filter order used by inbox_screen.
  static const tabAll = 0;
  static const tabUnread = 1;
  static const tabRead = 2;
  static const tabSent = 3;

  /// How long a fetched inbox stays "fresh" before [loadIfNeeded] refetches.
  static const _ttl = Duration(minutes: 3);

  /// Minimum gap between network refetches (throttles notification reloads).
  static const _minRefetchGap = Duration(seconds: 15);

  static const _inboxCacheKey = 'hermes.email_cache.inbox';
  static const _inboxTsKey = 'hermes.email_cache.inbox_ts';

  /// The full inbox (read + unread) — the single source the tabs filter from.
  List<EmailMessage> _inbox = [];
  DateTime? _inboxFetchedAt;

  /// Sent mail, lazily loaded when the Sent tab is first opened.
  List<EmailMessage> _sent = [];
  DateTime? _sentFetchedAt;

  bool _loading = false;
  bool get loading => _loading;

  bool _notConnected = false;
  bool get notConnected => _notConnected;

  String? _error;
  String? get error => _error;

  int _tabIndex = tabAll;
  int get tabIndex => _tabIndex;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  bool _hydrated = false;

  /// The messages visible for the current tab + search, filtered in memory.
  List<EmailMessage> get messages {
    Iterable<EmailMessage> src = _tabIndex == tabSent ? _sent : _inbox;
    if (_tabIndex == tabUnread) src = src.where((m) => m.unread);
    if (_tabIndex == tabRead) src = src.where((m) => !m.unread);

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      src = src.where((m) =>
          m.subject.toLowerCase().contains(q) ||
          m.from.display.toLowerCase().contains(q) ||
          m.snippet.toLowerCase().contains(q) ||
          (m.to ?? '').toLowerCase().contains(q));
    }
    return List.unmodifiable(src);
  }

  /// Unread count is always derived from the full inbox, not the current view.
  int get unreadCount => _inbox.where((m) => m.unread).length;

  bool get _inboxFresh =>
      _inboxFetchedAt != null &&
      DateTime.now().difference(_inboxFetchedAt!) < _ttl;

  // -- tab / search (both purely local) ---------------------------------------

  void setTabIndex(int idx) {
    if (_tabIndex == idx) return;
    _tabIndex = idx;
    notifyListeners();
    if (idx == tabSent) _loadSentIfNeeded();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners(); // local filter — no network, no debounce needed
  }

  // -- loading ----------------------------------------------------------------

  /// Called when the Inbox opens. Paints from cache instantly, and only hits the
  /// network when the cached inbox is missing or older than [_ttl].
  Future<void> loadIfNeeded() async {
    if (_loading) return;
    if (!_hydrated) {
      await _hydrateFromCache();
      _hydrated = true;
    }
    if (_inbox.isNotEmpty && _inboxFresh) {
      notifyListeners();
      return;
    }
    await refresh();
  }

  /// Force a network refetch (pull-to-refresh). Public alias kept as [load] for
  /// existing callers.
  Future<void> load({String? query}) => refresh();

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _inbox = await _repo.list(query: 'label:inbox', max: 50);
      _inboxFetchedAt = DateTime.now();
      _notConnected = false;
      await _persistInbox();
    } on HermesApiException catch (e) {
      if (e.statusCode == 503 ||
          e.message.toLowerCase().contains('not connected')) {
        _notConnected = true;
      } else {
        _error = e.message;
      }
    } catch (e) {
      _error = 'Could not load email: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Refetch only if the inbox is stale beyond the throttle window. Used by the
  /// notification listener so a burst of pushes doesn't hammer the gateway.
  Future<void> refreshIfStale() async {
    if (_loading) return;
    if (_inboxFetchedAt != null &&
        DateTime.now().difference(_inboxFetchedAt!) < _minRefetchGap) {
      return;
    }
    await refresh();
  }

  Future<void> _loadSentIfNeeded() async {
    if (_loading) return;
    if (_sent.isNotEmpty &&
        _sentFetchedAt != null &&
        DateTime.now().difference(_sentFetchedAt!) < _ttl) {
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _sent = await _repo.list(query: 'label:sent', max: 50, folder: 'sent');
      _sentFetchedAt = DateTime.now();
      _notConnected = false;
    } on HermesApiException catch (e) {
      if (e.statusCode == 503 ||
          e.message.toLowerCase().contains('not connected')) {
        _notConnected = true;
      } else {
        _error = e.message;
      }
    } catch (e) {
      _error = 'Could not load sent mail: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // -- cache persistence ------------------------------------------------------

  Future<void> _hydrateFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_inboxCacheKey);
      if (raw != null && raw.isNotEmpty) {
        _inbox = raw
            .map((s) {
              try {
                return EmailMessage.fromJson(
                    jsonDecode(s) as Map<String, dynamic>);
              } catch (_) {
                return null;
              }
            })
            .whereType<EmailMessage>()
            .toList();
      }
      final ts = prefs.getInt(_inboxTsKey);
      if (ts != null) {
        _inboxFetchedAt = DateTime.fromMillisecondsSinceEpoch(ts);
      }
    } catch (_) {}
  }

  Future<void> _persistInbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _inboxCacheKey,
        _inbox.map((m) => jsonEncode(m.toJson())).toList(),
      );
      await prefs.setInt(
        _inboxTsKey,
        (_inboxFetchedAt ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  // -- local read mutations ---------------------------------------------------

  EmailMessage _asRead(EmailMessage m) => EmailMessage(
        id: m.id,
        threadId: m.threadId,
        from: m.from,
        subject: m.subject,
        snippet: m.snippet,
        date: m.date,
        unread: false,
        to: m.to,
        body: m.body,
        messageIdHeader: m.messageIdHeader,
      );

  /// Reflect a read locally (after opening a message) without a full reload.
  void markReadLocally(String id) {
    final i = _inbox.indexWhere((m) => m.id == id);
    if (i != -1 && _inbox[i].unread) {
      _inbox[i] = _asRead(_inbox[i]);
      notifyListeners();
      _persistInbox();
    }
  }

  /// Mark all unread messages as read.
  Future<void> markAllRead() async {
    final unread = _inbox.where((m) => m.unread).toList();
    if (unread.isEmpty) return;
    for (var i = 0; i < _inbox.length; i++) {
      if (_inbox[i].unread) _inbox[i] = _asRead(_inbox[i]);
    }
    notifyListeners();
    await _persistInbox();
    await Future.wait(unread.map((m) => _repo.markRead(m.id)));
  }

  Map<String, List<EmailMessage>> get categoryDigests {
    final Map<String, List<EmailMessage>> groups = {
      'Work & Projects': [],
      'Personal': [],
      'Social & Invites': [],
      'Updates & Promos': [],
    };

    for (final m in messages) {
      final subject = m.subject.toLowerCase();
      final snippet = m.snippet.toLowerCase();
      final from = m.from.display.toLowerCase();

      if (subject.contains('deploy') || subject.contains('review') ||
          subject.contains('schedule') || subject.contains('deadline') ||
          subject.contains('task') || subject.contains('project') ||
          subject.contains('work') || subject.contains('meeting') ||
          snippet.contains('meeting') || snippet.contains('task')) {
        groups['Work & Projects']!.add(m);
      } else if (from.contains('linkedin') || from.contains('facebook') ||
          from.contains('twitter') || from.contains('instagram') ||
          subject.contains('invite') || subject.contains('social') ||
          snippet.contains('invite')) {
        groups['Social & Invites']!.add(m);
      } else if (subject.contains('offer') || subject.contains('discount') ||
          subject.contains('newsletter') || subject.contains('update') ||
          subject.contains('receipt') || subject.contains('invoice') ||
          snippet.contains('receipt') || snippet.contains('newsletter')) {
        groups['Updates & Promos']!.add(m);
      } else {
        groups['Personal']!.add(m);
      }
    }

    groups.removeWhere((k, v) => v.isEmpty);
    return groups;
  }

  Future<void> markCategoryRead(List<EmailMessage> list) async {
    final unread = list.where((m) => m.unread).toList();
    if (unread.isEmpty) return;
    for (final m in unread) {
      markReadLocally(m.id);
    }
    await Future.wait(unread.map((m) => _repo.markRead(m.id)));
  }
}
