import 'package:flutter/material.dart';

import 'app.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/notification_service.dart';
import 'data/services/reminder_service.dart';
import 'data/services/settings_service.dart';
import 'ui/core/theme_controller.dart';
import 'ui/features/voice/overlay/overlay_orb_entry.dart';

/// Separate Flutter entrypoint for the Android floating-orb overlay window.
///
/// `flutter_overlay_window` launches a dedicated engine and resolves the Dart
/// symbol named `overlayMain` — it must live here in `main.dart` and carry the
/// `vm:entry-point` pragma so tree-shaking keeps it.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayOrbApp());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hydrate connection settings + theme before the first frame so the root gate
  // can immediately choose onboarding vs. shell with the right theme, no flash.
  final settingsRepository = SettingsRepository(SettingsService());
  await settingsRepository.load();
  final themeController = await ThemeController.load();

  // Start listening for proactive pushes on the ntfy topic, and restart the
  // subscription whenever the settings (topic/server) change.
  final notificationService = NotificationService();
  await notificationService.start(settingsRepository.current);
  settingsRepository.addListener(
    () => notificationService.start(settingsRepository.current),
  );

  // On-device alarms: hydrate the saved list and re-arm them with the OS.
  final reminderService = ReminderService(notificationService);
  await reminderService.load();

  runApp(HermesApp(
    settingsRepository: settingsRepository,
    notificationService: notificationService,
    reminderService: reminderService,
    themeController: themeController,
  ));
}
