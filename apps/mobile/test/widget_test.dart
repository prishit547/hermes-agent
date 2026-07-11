// Smoke test: with no configured server the app shows the onboarding screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/app.dart';
import 'package:hermes_mobile/data/repositories/settings_repository.dart';
import 'package:hermes_mobile/data/services/notification_service.dart';
import 'package:hermes_mobile/data/services/reminder_service.dart';
import 'package:hermes_mobile/data/services/settings_service.dart';
import 'package:hermes_mobile/ui/core/theme_controller.dart';

void main() {
  testWidgets('shows onboarding when unconfigured', (tester) async {
    final repo = SettingsRepository(SettingsService());
    final notifications = NotificationService();

    await tester.pumpWidget(HermesApp(
      settingsRepository: repo,
      notificationService: notifications,
      reminderService: ReminderService(notifications),
      themeController: ThemeController(),
    ));
    await tester.pump();

    expect(find.text('Connect to Hermes'), findsOneWidget);
  });
}
