import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/chat_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import '../reminders/reminders_screen.dart';
import '../settings/views/settings_screen.dart';
import '../shell/shell_controller.dart';

const kAssistantName = 'Atlantic';

class _Task {
  _Task(this.title, this.time, this.done);
  final String title;
  final String time;
  bool done;
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _tasks = [
    _Task('Pick up prescription', '5:00', false),
    _Task('Reply to Alex', '', false),
    _Task('Book flights for SF', '', true),
  ];

  bool? _connected;

  @override
  void initState() {
    super.initState();
    _ping();
  }

  Future<void> _ping() async {
    final connected = await context.read<ChatRepository>().ping();
    if (mounted) setState(() => _connected = connected);
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
    return '${days[now.weekday - 1]} · ${months[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final shell = context.read<ShellController>();
    final serverName = _serverLabel(context);

    return ListView(
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
                      TextSpan(text: '$_greeting\n', style: atlSerif(size: 38, color: atl.text)),
                      TextSpan(
                        text: 'Rishit',
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
                child: Text('R',
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
        FadeInUp(delay: const Duration(milliseconds: 90), child: _BriefingCard(atl: atl)),
        const SizedBox(height: 17),

        // Up next
        FadeInUp(
          delay: const Duration(milliseconds: 140),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionRow(atl, 'Up next', trailing: 'in 3h 20m'),
              const SizedBox(height: 11),
              _card(
                atl,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _eventRow(atl, AtlColors.eventPink, 'Dentist appointment',
                        'Downtown Dental · 8 min away', '2:00'),
                    Divider(height: 1, color: atl.divider, indent: 15, endIndent: 15),
                    _eventRow(atl, AtlColors.eventGold, 'Call with Sam',
                        'Product sync · Google Meet', '4:00'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),

        // Tasks
        FadeInUp(
          delay: const Duration(milliseconds: 190),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Due today · tap to check',
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
                    for (var i = 0; i < _tasks.length; i++)
                      _taskRow(atl, _tasks[i], i),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),

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
            ],
          ),
        ),
      ],
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

  Widget _taskRow(AtlColors atl, _Task task, int i) => Pressable(
        onTap: () => setState(() => task.done = !task.done),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: i == _tasks.length - 1
                  ? BorderSide.none
                  : BorderSide(color: atl.divider),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: task.done ? atl.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: task.done ? null : Border.all(color: atl.text3, width: 1.6),
                ),
                child: task.done
                    ? Icon(Icons.check, size: 13, color: atl.accentInk)
                    : null,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(task.title,
                    style: atlSans(
                        size: 15,
                        color: task.done ? atl.text3 : atl.text,
                        decoration: task.done ? TextDecoration.lineThrough : null)),
              ),
              if (task.time.isNotEmpty)
                Text(task.time, style: atlMono(size: 12, color: atl.text3)),
            ],
          ),
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
  const _BriefingCard({required this.atl});
  final AtlColors atl;

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
                Text(
                  "Clear skies, 72°. Three events, two tasks. Afternoon's busy — "
                  "dentist at 2, then Sam at 4. Your morning is free if you'd like to write.",
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
