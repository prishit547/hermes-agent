import 'package:flutter/foundation.dart';

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

  String _query = 'is:unread';
  String get query => _query;

  bool _loadedOnce = false;

  int get unreadCount => _messages.where((m) => m.unread).length;

  /// Load once on first Inbox open; pull-to-refresh calls [load] directly.
  Future<void> loadIfNeeded() async {
    if (_loadedOnce || _loading) return;
    await load();
  }

  Future<void> load({String? query}) async {
    _loadedOnce = true;
    if (query != null) _query = query;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _messages = await _repo.list(query: _query, max: 25);
      _notConnected = false;
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
      notifyListeners();
    }
  }
}
