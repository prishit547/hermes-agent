import 'package:flutter/foundation.dart';

import '../../../../data/repositories/chat_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/connection_settings.dart';

/// Result of a "test connection" probe, surfaced on the settings screen.
enum ConnectionProbe { idle, testing, ok, failed }

/// Presentation logic for the settings/onboarding screen: edits the server URL
/// and API key, persists them through [SettingsRepository], and can probe the
/// endpoint's `/health` before the user commits.
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required SettingsRepository settingsRepository,
    required ChatRepository chatRepository,
  })  : _settings = settingsRepository,
        _chat = chatRepository {
    baseUrl = _settings.current.baseUrl;
    apiKey = _settings.current.apiKey;
    ntfyServer = _settings.current.ntfyServer;
    ntfyTopic = _settings.current.ntfyTopic;
  }

  final SettingsRepository _settings;
  final ChatRepository _chat;

  String baseUrl = '';
  String apiKey = '';
  String ntfyServer = '';
  String ntfyTopic = '';

  ConnectionProbe _probe = ConnectionProbe.idle;
  ConnectionProbe get probe => _probe;

  bool get isConfigured => _settings.current.isConfigured;

  void setBaseUrl(String value) {
    baseUrl = value;
    _probe = ConnectionProbe.idle;
    notifyListeners();
  }

  void setApiKey(String value) {
    apiKey = value;
    _probe = ConnectionProbe.idle;
    notifyListeners();
  }

  void setNtfyServer(String value) {
    ntfyServer = value;
    notifyListeners();
  }

  void setNtfyTopic(String value) {
    ntfyTopic = value;
    notifyListeners();
  }

  Future<void> save() async {
    await _settings.update(
      ConnectionSettings(
        baseUrl: baseUrl,
        apiKey: apiKey,
        ntfyServer: ntfyServer.trim().isEmpty ? 'https://ntfy.sh' : ntfyServer,
        ntfyTopic: ntfyTopic,
      ),
    );
    notifyListeners();
  }

  /// Persist first (so the probe uses the entered values) then hit `/health`.
  Future<void> testConnection() async {
    _probe = ConnectionProbe.testing;
    notifyListeners();
    await save();
    final ok = await _chat.ping();
    _probe = ok ? ConnectionProbe.ok : ConnectionProbe.failed;
    notifyListeners();
  }
}
