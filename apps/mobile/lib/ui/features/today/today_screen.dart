import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/chat_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/models/calendar_event.dart';
import '../../../domain/models/local_reminder.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import '../email/email_view_model.dart';
import '../music/music_screen.dart';
import '../reminders/reminders_screen.dart';
import '../settings/views/settings_screen.dart';
import '../shell/shell_controller.dart';
import 'today_view_model.dart';

const kAssistantName = 'Atlantic';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool? _connected;
  Timer? _clockTimer;
  TodayTimePeriod? _lastPeriod;

  @override
  void initState() {
    super.initState();
    _ping();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    final initialPeriod = _getPeriod();
    _lastPeriod = initialPeriod;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TodayViewModel>().loadIfNeeded(period: initialPeriod);
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _ping() async {
    final connected = await context.read<ChatRepository>().ping();
    if (mounted) setState(() => _connected = connected);
  }

  Color _dotFor(CalendarKind kind) => switch (kind) {
        CalendarKind.event => AtlColors.eventBlue,
        CalendarKind.task => AtlColors.eventGold,
        CalendarKind.alarm => AtlColors.eventPink,
      };

  String _fmtTime(DateTime t) => TimeOfDay.fromDateTime(t).format(context);

  TodayTimePeriod _getPeriod() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) {
      return TodayTimePeriod.morningRise;
    } else if (hour >= 12 && hour < 18) {
      return TodayTimePeriod.deepWork;
    } else {
      return TodayTimePeriod.windDown;
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  String get _dateLine {
    final now = DateTime.now();
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    final minStr = now.minute.toString().padLeft(2, '0');
    final hour = now.hour == 0
        ? 12
        : now.hour > 12
            ? now.hour - 12
            : now.hour;
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minStr $amPm';
    return '${days[now.weekday - 1]} · ${months[now.month - 1]} ${now.day} · $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final shell = context.read<ShellController>();
    final vm = context.watch<TodayViewModel>();
    final serverName = _serverLabel(context);
    final name = context.watch<SettingsRepository>().current.userName.trim();
    final avatarLetter =
        name.isNotEmpty ? name[0].toUpperCase() : kAssistantName[0];

    final period = _getPeriod();
    if (_lastPeriod != period) {
      _lastPeriod = period;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<TodayViewModel>().load(period: period);
        }
      });
    }

    final currentBg = switch (period) {
      TodayTimePeriod.morningRise => const RadialGradient(
          center: Alignment(0, -1.12),
          radius: 1.2,
          colors: [Color(0xFF331E12), Color(0xFF0C0907)],
          stops: [0.0, 0.65],
        ),
      TodayTimePeriod.deepWork => const RadialGradient(
          center: Alignment(0, -1.12),
          radius: 1.2,
          colors: [Color(0xFF0F1E36), Color(0xFF060910)],
          stops: [0.0, 0.65],
        ),
      TodayTimePeriod.windDown => const RadialGradient(
          center: Alignment(0, -1.12),
          radius: 1.2,
          colors: [Color(0xFF231338), Color(0xFF090510)],
          stops: [0.0, 0.65],
        ),
    };

    final List<Widget> bodyChildren = [];

    // Header
    bodyChildren.add(_buildHeader(atl, name, avatarLetter));
    bodyChildren.add(const SizedBox(height: 16));

    // Connection pill
    bodyChildren.add(_ConnectionPill(connected: _connected, serverName: serverName));
    bodyChildren.add(const SizedBox(height: 18));

    if (period == TodayTimePeriod.morningRise) {
      bodyChildren.add(
        FadeInUp(
          delay: const Duration(milliseconds: 40),
          child: _BriefingCard(atl: atl, text: vm.briefing, loading: vm.loading),
        ),
      );
      bodyChildren.add(const SizedBox(height: 17));

      if (vm.loading || vm.upNext.isNotEmpty) {
        bodyChildren.add(FadeInUp(
          delay: const Duration(milliseconds: 90),
          child: _buildUpNext(atl, vm),
        ));
        bodyChildren.add(const SizedBox(height: 17));
      }

      bodyChildren.add(_buildAskBar(shell, atl));
      bodyChildren.add(const SizedBox(height: 18));

      if (vm.dueToday.isNotEmpty) {
        bodyChildren.add(FadeInUp(
          delay: const Duration(milliseconds: 190),
          child: _buildDueToday(atl, vm),
        ));
        bodyChildren.add(const SizedBox(height: 17));
      }

      bodyChildren.add(_buildQuickActions(atl, shell));
    } else if (period == TodayTimePeriod.deepWork) {
      bodyChildren.add(_buildAskBar(shell, atl));
      bodyChildren.add(const SizedBox(height: 18));

      if (vm.dueToday.isNotEmpty) {
        bodyChildren.add(FadeInUp(
          delay: const Duration(milliseconds: 90),
          child: _buildDueToday(atl, vm),
        ));
        bodyChildren.add(const SizedBox(height: 17));
      }

      if (vm.loading || vm.upNext.isNotEmpty) {
        bodyChildren.add(FadeInUp(
          delay: const Duration(milliseconds: 140),
          child: _buildUpNext(atl, vm),
        ));
        bodyChildren.add(const SizedBox(height: 17));
      }

      bodyChildren.add(
        FadeInUp(
          delay: const Duration(milliseconds: 190),
          child: _BriefingCard(atl: atl, text: vm.briefing, loading: vm.loading),
        ),
      );
      bodyChildren.add(const SizedBox(height: 17));

      bodyChildren.add(_buildQuickActions(atl, shell));
    } else {
      bodyChildren.add(FadeInUp(
        delay: const Duration(milliseconds: 40),
        child: _buildEmailDigestSummary(context, atl),
      ));
      bodyChildren.add(const SizedBox(height: 17));

      bodyChildren.add(FadeInUp(
        delay: const Duration(milliseconds: 90),
        child: _buildMusicCard(context, atl),
      ));
      bodyChildren.add(const SizedBox(height: 17));

      if (vm.loading || vm.upNext.isNotEmpty) {
        bodyChildren.add(FadeInUp(
          delay: const Duration(milliseconds: 140),
          child: _buildUpNext(atl, vm),
        ));
        bodyChildren.add(const SizedBox(height: 17));
      }

      bodyChildren.add(_buildAskBar(shell, atl));
      bodyChildren.add(const SizedBox(height: 18));

      bodyChildren.add(
        FadeInUp(
          delay: const Duration(milliseconds: 240),
          child: _BriefingCard(atl: atl, text: vm.briefing, loading: vm.loading),
        ),
      );
      bodyChildren.add(const SizedBox(height: 17));

      bodyChildren.add(_buildQuickActions(atl, shell));
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(gradient: currentBg),
      child: RefreshIndicator(
        onRefresh: () => context.read<TodayViewModel>().load(period: period),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: ListView(
            key: ValueKey<TodayTimePeriod>(period),
            padding: const EdgeInsets.fromLTRB(21, 6, 21, 24),
            children: bodyChildren,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AtlColors atl, String name, String avatarLetter) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_dateLine,
                  style: atlSans(
                      size: 13,
                      color: atl.text2,
                      weight: FontWeight.w500,
                      letterSpacing: 0.4)),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                      text: name.isEmpty ? _greeting.replaceAll(',', '') : '$_greeting\n',
                      style: atlSerif(size: 38, color: atl.text)),
                  if (name.isNotEmpty)
                    TextSpan(
                      text: name,
                      style: atlSerif(size: 38, color: atl.accent, style: FontStyle.italic),
                    ),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(top: 24),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
              ),
            ),
            alignment: Alignment.center,
            child: Text(avatarLetter,
                style: atlSans(size: 15, color: const Color(0xFF0A0A14), weight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildAskBar(ShellController shell, AtlColors atl) {
    return FadeInUp(
      delay: const Duration(milliseconds: 40),
      child: Pressable(
        onTap: shell.openVoice,
        child: _card(
          atl,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: atl.text3),
              const SizedBox(width: 11),
              Expanded(
                child: Text('Ask $kAssistantName anything…',
                    style: atlSans(size: 15, color: atl.text3)),
              ),
              _miniOrb(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpNext(AtlColors atl, TodayViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionRow(atl, 'Up next', trailing: vm.nextInLabel),
        const SizedBox(height: 11),
        _card(
          atl,
          padding: EdgeInsets.zero,
          child: vm.loading && vm.upNext.isEmpty
              ? _skeletonRow(atl)
              : Column(
                  children: [
                    for (var i = 0; i < vm.upNext.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: atl.divider, indent: 15, endIndent: 15),
                      _eventRow(
                        atl,
                        _dotFor(vm.upNext[i].kind),
                        vm.upNext[i].title,
                        vm.upNext[i].subtitle ?? '',
                        _fmtTime(vm.upNext[i].start),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDueToday(AtlColors atl, TodayViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Due today · reminders',
            style: atlSans(
                size: 12,
                color: atl.text2,
                weight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 11),
        _card(
          atl,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < vm.dueToday.length; i++)
                _reminderRow(atl, vm.dueToday[i], i == vm.dueToday.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(AtlColors atl, ShellController shell) {
    return FadeInUp(
      delay: const Duration(milliseconds: 240),
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          _chip(atl, Icons.add, 'Reminder', () => openReminders(context)),
          _chip(atl, Icons.mic_none, 'Voice memo', shell.openVoice),
          _chip(atl, Icons.calendar_today_outlined, 'Add event',
              () => shell.go(AtlTab.calendar)),
          _chip(atl, Icons.music_note_outlined, 'Music', () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MusicScreen()),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmailDigestSummary(BuildContext context, AtlColors atl) {
    final email = context.watch<EmailViewModel>();
    final shell = context.read<ShellController>();

    return Pressable(
      onTap: () => shell.go(AtlTab.inbox),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: atl.hairline),
          boxShadow: atl.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: atl.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.email_outlined, color: atl.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Email Digests',
                    style: atlSans(size: 14, color: atl.text, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email.unreadCount > 0
                        ? 'You have ${email.unreadCount} unread emails. Tap to read digests.'
                        : 'You\'re all caught up on email.',
                    style: atlSans(size: 12, color: atl.text2, height: 1.4),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: atl.text3, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicCard(BuildContext context, AtlColors atl) {
    return Pressable(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MusicScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: atl.hairline),
          boxShadow: atl.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: atl.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.music_note, color: atl.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wind-down Music',
                    style: atlSans(size: 14, color: atl.text, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Listen to soothing sounds and prepare for tomorrow.',
                    style: atlSans(size: 12, color: atl.text2, height: 1.4),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: atl.text3, size: 20),
          ],
        ),
      ),
    );
  }

  String? _serverLabel(BuildContext context) {
    final url = context.read<SettingsRepository>().current.baseUrl;
    final host = Uri.tryParse(url)?.host;
    return (host == null || host.isEmpty) ? null : host;
  }

  Widget _card(AtlColors atl, {required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: child,
    );
  }

  Widget _miniOrb() => Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
          ),
        ),
        child: const Icon(Icons.mic_none, size: 17, color: Color(0xFF0A0A14)),
      );

  Widget _sectionRow(AtlColors atl, String label, {String? trailing}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.toUpperCase(),
              style: atlSans(
                  size: 12, color: atl.text2, weight: FontWeight.w600, letterSpacing: 1)),
          if (trailing != null)
            Text(trailing, style: atlMono(size: 12, color: atl.accent)),
        ],
      );

  Widget _eventRow(AtlColors atl, Color dot, String title, String sub, String time) => Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 38,
              decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sub, style: atlSans(size: 13, color: atl.text2)),
                ],
              ),
            ),
            Text(time, style: atlMono(size: 15, color: atl.text)),
          ],
        ),
      );

  Widget _reminderRow(AtlColors atl, LocalReminder r, bool last) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: last ? BorderSide.none : BorderSide(color: atl.divider),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_none, size: 20, color: atl.accent),
            const SizedBox(width: 13),
            Expanded(
              child: Text(r.title, style: atlSans(size: 15, color: atl.text)),
            ),
            Text(_fmtTime(r.time), style: atlMono(size: 12, color: atl.text3)),
          ],
        ),
      );

  Widget _skeletonRow(AtlColors atl) => Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 13),
            Text('Loading your day…', style: atlSans(size: 14, color: atl.text3)),
          ],
        ),
      );

  Widget _chip(AtlColors atl, IconData icon, String label, VoidCallback onTap) =>
      Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: atl.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: atl.hairline),
            boxShadow: atl.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: atl.accent),
              const SizedBox(width: 7),
              Text(label, style: atlSans(size: 13, color: atl.text, weight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.connected, required this.serverName});
  final bool? connected;
  final String? serverName;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final ok = connected == true;
    final label = connected == null
        ? 'Connecting…'
        : ok
            ? 'Connected · ${serverName ?? 'gateway'}'
            : 'Offline';
    final color = ok ? const Color(0xFF1EA88A) : atl.text3;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: ok ? const Color(0x1F7FEBD0) : atl.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ok ? const Color(0x4D7FEBD0) : atl.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 7),
            Text(label, style: atlSans(size: 12, color: color, weight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({required this.atl, required this.text, required this.loading});
  final AtlColors atl;
  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0x2E8FE9FF), atl.surface, const Color(0x26F4A9D6)],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.brightness_2_outlined, size: 17, color: atl.accent),
                        const SizedBox(width: 8),
                        Text('Daily briefing',
                            style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                      ],
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: atl.accent),
                      child: Icon(Icons.play_arrow, size: 18, color: atl.accentInk),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                if (loading && text.isEmpty)
                  Row(
                    children: [
                      const SizedBox(
                          width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Preparing your briefing…',
                          style: atlSans(size: 14, color: atl.text3)),
                    ],
                  )
                else
                  Text(
                    text.isEmpty
                        ? 'Pull to refresh for your daily briefing.'
                        : text,
                    style: atlSans(size: 14, color: atl.text2, height: 1.6),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
