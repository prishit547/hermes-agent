import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/repositories/email_repository.dart';
import '../../../data/services/hermes_api_client.dart';
import '../../../domain/models/email_message.dart';

/// Backs the email surfaces: loads the inbox (unread by default), tracks the
/// "Gmail not connected" state, and reflects local read/sent changes.
class EmailViewModel extends ChangeNotifier {
  EmailViewModel(this._repo);

  final EmailRepository _repo;

  List<EmailMessage> _messages = [];
  List<EmailMessage> get messages => List.unmodifiable(_messages);

  bool _loading = false;
  bool get loading => _loading;

  bool _notConnected = false;
  bool get notConnected => _notConnected;

  String? _error;
  String? get error => _error;

  int _tabIndex = 0; // 0 = All Mails, 1 = Unread Mails, 2 = Read Mails
  int get tabIndex => _tabIndex;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  String get effectiveQuery {
    final String base;
    if (_tabIndex == 0) {
      base = 'label:inbox';
    } else if (_tabIndex == 1) {
      base = 'label:inbox is:unread';
    } else {
      base = 'label:inbox is:read';
    }

    if (_searchQuery.trim().isEmpty) {
      return base;
    } else {
      return '$base ${_searchQuery.trim()}';
    }
  }

  bool _loadedOnce = false;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  String get _cacheKey {
    final String label;
    if (_tabIndex == 0) {
      label = 'all';
    } else if (_tabIndex == 1) {
      label = 'unread';
    } else {
      label = 'read';
    }
    return 'hermes.email_cache.$label';
  }

  void setTabIndex(int idx) {
    if (_tabIndex != idx) {
      _tabIndex = idx;
      _messages = [];
      _loadedOnce = false;
      notifyListeners();
      loadIfNeeded();
    }
  }

  void setSearchQuery(String query) {
    if (_searchQuery != query) {
      _searchQuery = query;
      load();
    }
  }

  /// Load once on first Inbox open; pull-to-refresh calls [load] directly.
  Future<void> loadIfNeeded() async {
    if (_loadedOnce || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        _messages = raw.map((s) {
          try {
            return EmailMessage.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<EmailMessage>().toList();

        if (_tabIndex == 0) {
          _unreadCount = _messages.where((m) => m.unread).length;
        } else if (_tabIndex == 1) {
          _unreadCount = _messages.length;
        }

        _loadedOnce = true;
        _loading = false;
        notifyListeners();
      }
    } catch (_) {}

    await load();
  }

  Future<void> load({String? query}) async {
    _loadedOnce = true;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final q = query ?? effectiveQuery;
      final next = await _repo.list(query: q, max: 25);
      _messages = next;
      _notConnected = false;

      if (_tabIndex == 0) {
        _unreadCount = _messages.where((m) => m.unread).length;
      } else if (_tabIndex == 1) {
        _unreadCount = _messages.length;
      }

      // Save to SharedPreferences cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _cacheKey,
        _messages.map((m) => jsonEncode(m.toJson())).toList(),
      );
    } on HermesApiException catch (e) {
      if (e.statusCode == 503 || e.message.toLowerCase().contains('not connected')) {
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

  /// Reflect a read locally (after opening a message) without a full reload.
  void markReadLocally(String id) {
    final i = _messages.indexWhere((m) => m.id == id);
    if (i != -1 && _messages[i].unread) {
      final m = _messages[i];
      _messages[i] = EmailMessage(
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
      _unreadCount = (_unreadCount - 1).clamp(0, 999);
      notifyListeners();

      // Save updated cache
      SharedPreferences.getInstance().then((prefs) {
        prefs.setStringList(
          _cacheKey,
          _messages.map((msg) => jsonEncode(msg.toJson())).toList(),
        );
      });
    }
  }

  /// Mark all visible unread messages as read in parallel.
  Future<void> markAllRead() async {
    final unread = _messages.where((m) => m.unread).toList();
    if (unread.isEmpty) return;

    for (final m in unread) {
      final i = _messages.indexWhere((msg) => msg.id == m.id);
      if (i != -1) {
        final old = _messages[i];
        _messages[i] = EmailMessage(
          id: old.id,
          threadId: old.threadId,
          from: old.from,
          subject: old.subject,
          snippet: old.snippet,
          date: old.date,
          unread: false,
          to: old.to,
          body: old.body,
          messageIdHeader: old.messageIdHeader,
        );
      }
    }
    _unreadCount = 0;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _cacheKey,
        _messages.map((m) => jsonEncode(m.toJson())).toList(),
      );
    } catch (_) {}

    await Future.wait(unread.map((m) => _repo.markRead(m.id)));
  }

  Map<String, List<EmailMessage>> get categoryDigests {
    final Map<String, List<EmailMessage>> groups = {
      'Work & Projects': [],
      'Personal': [],
      'Social & Invites': [],
      'Updates & Promos': [],
    };

    for (final m in _messages) {
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
