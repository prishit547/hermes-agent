// Smoke test: with the intro already seen and no configured server, the app
// shows the connection form.
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/app.dart';
import 'package:hermes_mobile/data/repositories/settings_repository.dart';
import 'package:hermes_mobile/data/services/notification_service.dart';
import 'package:hermes_mobile/data/services/reminder_service.dart';
import 'package:hermes_mobile/data/services/settings_service.dart';
import 'package:hermes_mobile/ui/core/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows onboarding when unconfigured', (tester) async {
    // The root gate reads this flag; mark the first-run intro as already seen
    // so we land on the connection form rather than the welcome pages.
    SharedPreferences.setMockInitialValues({'hermes.intro_seen': true});

    final repo = SettingsRepository(SettingsService());
    final notifications = NotificationService();
    final reminders = ReminderService(notifications);

    await tester.pumpWidget(HermesApp(
      settingsRepository: repo,
      notificationService: notifications,
      reminderService: reminders,
      themeController: ThemeController(),
    ));
    // Let the async intro-flag read resolve, then render.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Connect to Hermes'), findsOneWidget);

    // ReminderService runs a periodic timer; cancel it before the body returns
    // so the test binding's pending-timer invariant is satisfied.
    reminders.dispose();
  });
}
