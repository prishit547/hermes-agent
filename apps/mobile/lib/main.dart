import 'package:flutter/material.dart';

import 'app.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/notification_service.dart';
import 'data/services/reminder_service.dart';
import 'data/services/settings_service.dart';
import 'ui/core/theme_controller.dart';

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
