import 'package:flutter/foundation.dart';

import '../../../../data/repositories/session_repository.dart';
import '../../../../domain/models/session_summary.dart';

/// Backs the conversation-history drawer: loads sessions with a scope filter
/// ("This app" vs "All devices") and exposes refresh/delete.
class SessionListViewModel extends ChangeNotifier {
  SessionListViewModel(this._repo);

  final SessionRepository _repo;

  List<SessionSummary> _sessions = [];
  List<SessionSummary> get sessions => List.unmodifiable(_sessions);

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// When true, list only this app's conversations (`source == api_server`);
  /// otherwise list conversations from every device/channel.
  bool _thisAppOnly = true;
  bool get thisAppOnly => _thisAppOnly;

  Future<void> setThisAppOnly(bool value) async {
    if (_thisAppOnly == value) return;
    _thisAppOnly = value;
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _sessions = await _repo.list(source: _thisAppOnly ? 'api_server' : null, limit: 100);
    } catch (e) {
      _error = 'Could not load conversations: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> delete(String id) async {
    try {
      await _repo.delete(id);
      _sessions.removeWhere((s) => s.id == id);
      notifyListeners();
    } catch (e) {
      _error = 'Delete failed: $e';
      notifyListeners();
    }
  }
}
