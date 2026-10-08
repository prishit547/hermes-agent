import 'package:flutter/foundation.dart';

import '../../../../data/repositories/chat_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/assistant_role_service.dart';
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
    AssistantRoleService? assistantRole,
  })  : _settings = settingsRepository,
        _chat = chatRepository,
        _assistantRole = assistantRole ?? AssistantRoleService() {
    baseUrl = _settings.current.baseUrl;
    apiKey = _settings.current.apiKey;
    ntfyServer = _settings.current.ntfyServer;
    ntfyTopic = _settings.current.ntfyTopic;
    userName = _settings.current.userName;
    refreshAssistantStatus();
  }

  final SettingsRepository _settings;
  final ChatRepository _chat;
  final AssistantRoleService _assistantRole;

  String baseUrl = '';
  String apiKey = '';
  String ntfyServer = '';
  String ntfyTopic = '';
  String userName = '';

  ConnectionProbe _probe = ConnectionProbe.idle;
  ConnectionProbe get probe => _probe;

  /// Whether Hermes is the phone's default digital assistant (Android). Null
  /// while the initial status check is in flight.
  bool? _assistantIsDefault;
  bool? get assistantIsDefault => _assistantIsDefault;

  /// Set briefly after a role request so the UI can explain that the user needs
  /// to pick Hermes in the settings screen that just opened.
  bool _assistantOpenedSettings = false;
  bool get assistantOpenedSettings => _assistantOpenedSettings;

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

  void setUserName(String value) {
    userName = value;
    notifyListeners();
  }

  Future<void> save() async {
    await _settings.update(
      ConnectionSettings(
        baseUrl: baseUrl,
        apiKey: apiKey,
        ntfyServer: ntfyServer.trim().isEmpty ? 'https://ntfy.sh' : ntfyServer,
        ntfyTopic: ntfyTopic,
        userName: userName,
      ),
    );
    notifyListeners();
  }

  /// Re-check whether Hermes holds the system assistant role. Cheap; safe to
  /// call on screen build and on app resume.
  Future<void> refreshAssistantStatus() async {
    final isDefault = await _assistantRole.isDefault();
    if (isDefault != _assistantIsDefault) {
      _assistantIsDefault = isDefault;
      notifyListeners();
    } else {
      _assistantIsDefault = isDefault;
    }
  }

  /// Ask the OS to make Hermes the default assistant. Tries the direct role
  /// request first; if the platform can't grant it that way, opens the assistant
  /// settings screen so the user can pick Hermes manually.
  Future<void> setAsDefaultAssistant() async {
    _assistantOpenedSettings = false;
    final result = await _assistantRole.requestRole();
    switch (result) {
      case AssistantRoleResult.granted:
        _assistantIsDefault = true;
      case AssistantRoleResult.denied:
      case AssistantRoleResult.cancelled:
        break;
      case AssistantRoleResult.unsupported:
        _assistantOpenedSettings = await _assistantRole.openSettings();
    }
    notifyListeners();
    // Status may have changed out-of-band (e.g. after the settings screen).
    await refreshAssistantStatus();
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
