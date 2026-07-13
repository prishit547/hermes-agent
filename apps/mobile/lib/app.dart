import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'data/repositories/calendar_repository.dart';
import 'data/repositories/chat_repository.dart';
import 'data/repositories/email_repository.dart';
import 'data/repositories/jobs_repository.dart';
import 'data/repositories/music_repository.dart';
import 'data/repositories/session_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/system_repository.dart';
import 'data/services/audio_service.dart';
import 'data/services/hermes_api_client.dart';
import 'data/services/music_player_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/reminder_service.dart';
import 'data/services/voice_stream_service.dart';
import 'ui/core/atl_theme.dart';
import 'ui/core/theme_controller.dart';
import 'ui/features/calendar/calendar_view_model.dart';
import 'ui/features/chat/view_models/chat_view_model.dart';
import 'ui/features/chat/view_models/session_list_view_model.dart';
import 'ui/features/email/email_view_model.dart';
import 'ui/features/music/music_view_model.dart';
import 'ui/features/today/today_view_model.dart';
import 'ui/features/settings/view_models/settings_view_model.dart';
import 'ui/features/settings/views/settings_screen.dart';
import 'ui/features/shell/home_shell.dart';
import 'ui/features/shell/shell_controller.dart';
import 'ui/features/voice/voice_view_model.dart';
import 'ui/features/voice/assistant_overlay_screen.dart';

/// Composition root. Builds the dependency graph once (services → repositories
/// → view models) and wires it into the widget tree with `provider`, themed
/// with the Atlantic design system.
class HermesApp extends StatelessWidget {
  const HermesApp({
    super.key,
    required this.settingsRepository,
    required this.notificationService,
    required this.reminderService,
    required this.themeController,
  });

  final SettingsRepository settingsRepository;
  final NotificationService notificationService;
  final ReminderService reminderService;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final apiClient = HermesApiClient();
    final audioService = AudioService();
    final chatRepository = ChatRepository(
      apiClient: apiClient,
      settingsRepository: settingsRepository,
    );
    final sessionRepository = SessionRepository(
      apiClient: apiClient,
      settingsRepository: settingsRepository,
    );
    final systemRepository = SystemRepository(
      apiClient: apiClient,
      settingsRepository: settingsRepository,
    );
    final jobsRepository = JobsRepository(
      apiClient: apiClient,
      settingsRepository: settingsRepository,
    );
    final voiceStreamService = VoiceStreamService(settingsRepository);
    final emailRepository = EmailRepository(
      apiClient: apiClient,
      settingsRepository: settingsRepository,
    );
    final calendarRepository = CalendarRepository(
      apiClient: apiClient,
      settingsRepository: settingsRepository,
    );
    final musicPlayerService = MusicPlayerService();
    final musicRepository = MusicRepository(
      apiClient: apiClient,
      settingsRepository: settingsRepository,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsRepository),
        ChangeNotifierProvider.value(value: notificationService),
        ChangeNotifierProvider.value(value: reminderService),
        ChangeNotifierProvider.value(value: themeController),
        Provider.value(value: chatRepository),
        Provider.value(value: sessionRepository),
        Provider.value(value: systemRepository),
        Provider.value(value: jobsRepository),
        Provider.value(value: audioService),
        Provider.value(value: voiceStreamService),
        Provider.value(value: emailRepository),
        Provider.value(value: musicRepository),
        ChangeNotifierProvider(create: (_) => ShellController()),
        ChangeNotifierProvider(
          create: (_) => ChatViewModel(
            chatRepository: chatRepository,
            sessionRepository: sessionRepository,
            audioService: audioService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SessionListViewModel(sessionRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => CalendarViewModel(
            calendarRepository: calendarRepository,
            chatRepository: chatRepository,
            reminderService: reminderService,
            jobsRepository: jobsRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => TodayViewModel(
            chatRepository: chatRepository,
            reminderService: reminderService,
          ),
        ),
        ChangeNotifierProvider(create: (_) => EmailViewModel(emailRepository)),
        ChangeNotifierProvider(
          create: (_) => MusicViewModel(
            repository: musicRepository,
            playerService: musicPlayerService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => VoiceViewModel(voiceStreamService, audioService),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel(
            settingsRepository: settingsRepository,
            chatRepository: chatRepository,
          ),
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (_, theme, _) => MaterialApp(
          title: 'Hermes',
          debugShowCheckedModeBanner: false,
          theme: buildAtlTheme(Brightness.light),
          darkTheme: buildAtlTheme(Brightness.dark),
          themeMode: theme.mode,
          initialRoute: '/',
          onGenerateRoute: (settings) {
            if (settings.name == '/assistant_overlay') {
              return PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AssistantOverlayScreen(),
                opaque: false,
                barrierColor: Colors.transparent,
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              );
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const _RootGate(),
            );
          },
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            SystemChrome.setSystemUIOverlayStyle(
              SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
              ),
            );
            return child!;
          },
        ),
      ),
    );
  }
}

/// Routes to onboarding until a server + key are configured, then to the shell.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>();
    if (!settings.current.isConfigured) {
      return const SettingsScreen(isOnboarding: true);
    }
    return const HomeShell();
  }
}
