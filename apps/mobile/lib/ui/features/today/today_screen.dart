import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/chat_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/models/calendar_event.dart';
import '../../../domain/models/local_reminder.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _ping();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TodayViewModel>().loadIfNeeded();
    });
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
    return '${days[now.weekday - 1]} · ${months[now.month - 1]} ${now.day}';
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

    return RefreshIndicator(
      onRefresh: () => context.read<TodayViewModel>().load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(21, 6, 21, 24),
        children: [
        // Header
        Row(
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
        ),
        const SizedBox(height: 16),

        // Connection pill
        _ConnectionPill(connected: _connected, serverName: serverName),
        const SizedBox(height: 18),

        // Ask bar
        FadeInUp(
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
        ),
        const SizedBox(height: 18),

        // Daily briefing
        FadeInUp(
            delay: const Duration(milliseconds: 90),
            child: _BriefingCard(atl: atl, text: vm.briefing, loading: vm.loading)),
        const SizedBox(height: 17),

        // Up next — real calendar events for today
        if (vm.loading || vm.upNext.isNotEmpty)
          FadeInUp(
            delay: const Duration(milliseconds: 140),
            child: Column(
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
            ),
          ),
        if (vm.loading || vm.upNext.isNotEmpty) const SizedBox(height: 17),

        // Due today — real on-device reminders
        if (vm.dueToday.isNotEmpty)
          FadeInUp(
            delay: const Duration(milliseconds: 190),
            child: Column(
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
            ),
          ),
        if (vm.dueToday.isNotEmpty) const SizedBox(height: 17),

        // Quick actions
        FadeInUp(
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
        ),
      ],
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
