import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/atl_theme.dart';
import '../calendar/calendar_screen.dart';
import '../chat/views/chat_screen.dart';
import '../inbox/inbox_screen.dart';
import '../music/mini_player.dart';
import '../today/today_screen.dart';
import '../voice/voice_overlay.dart';
import 'shell_controller.dart';

/// Root scaffold: the app-background gradient, the active tab screen (with an
/// animated cross-fade/slide transition), the frosted bottom tab bar with the
/// emphasized center Halo control, and the voice overlay layered on top.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _screens = [
    TodayScreen(),
    ChatScreen(),
    CalendarScreen(),
    InboxScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final shell = context.watch<ShellController>();

    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.025),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(shell.tab),
                  child: _screens[shell.tab.index],
                ),
              ),
            ),
            if (shell.voiceOpen) const Positioned.fill(child: VoiceOverlay()),
          ],
        ),
        bottomNavigationBar: shell.voiceOpen
            ? null
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [MiniPlayer(), _AtlTabBar()],
              ),
      ),
    );
  }
}

class _AtlTabBar extends StatelessWidget {
  const _AtlTabBar();

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    // watch (not read) so the highlight follows tab changes even though the
    // widget is constructed const in the Scaffold.
    final shell = context.watch<ShellController>();
    final active = shell.tab;

    // Trim the oversized home-indicator gap while keeping a little clearance.
    final rawBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPad = rawBottom > 0 ? (rawBottom - 16).clamp(6.0, 20.0) : 8.0;

    return Stack(
      clipBehavior: Clip.none, // let the raised center orb overflow upward
      children: [
        // Frosted background — only this layer is clipped.
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: atl.frost,
                  border: Border(top: BorderSide(color: atl.divider)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(8, 7, 8, bottomPad),
          child: Row(
            children: [
              _TabItem(
                label: 'Today',
                active: active == AtlTab.today,
                onTap: () => shell.go(AtlTab.today),
                icon: Icons.home_outlined,
              ),
              _TabItem(
                label: 'Chat',
                active: active == AtlTab.chat,
                onTap: () => shell.go(AtlTab.chat),
                icon: Icons.chat_bubble_outline,
              ),
              Expanded(child: _CenterOrbButton(onTap: shell.openVoice)),
              _TabItem(
                label: 'Calendar',
                active: active == AtlTab.calendar,
                onTap: () => shell.go(AtlTab.calendar),
                icon: Icons.calendar_today_outlined,
              ),
              _TabItem(
                label: 'Inbox',
                active: active == AtlTab.inbox,
                onTap: () => shell.go(AtlTab.inbox),
                icon: Icons.inbox_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.active,
    required this.onTap,
    required this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final color = active ? atl.accent : atl.navInactive;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active tab gets a gentle pop; color eases between states.
            AnimatedScale(
              scale: active ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: const Duration(milliseconds: 220),
                builder: (_, c, _) => Icon(icon, size: 23, color: c),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: atlSans(size: 10, color: color, weight: FontWeight.w500),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

/// The emphasized center control — a mini Halo sphere floating above the bar.
/// It renders larger than its layout slot and is raised via a transform; the
/// parent Stack uses `Clip.none` so it overflows cleanly instead of clipping.
class _CenterOrbButton extends StatefulWidget {
  const _CenterOrbButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CenterOrbButton> createState() => _CenterOrbButtonState();
}

class _CenterOrbButtonState extends State<_CenterOrbButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  bool _down = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: SizedBox(
        height: 44,
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, -16),
            child: AnimatedScale(
              scale: _down ? 0.92 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) {
                  final t = _pulse.value;
                  return Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(0.24, 0.36),
                        colors: [
                          Colors.white,
                          AtlColors.halo1,
                          AtlColors.halo3,
                          Color(0xFFD9E9FF),
                        ],
                        stops: [0.08, 0.5, 0.7, 1.0],
                      ),
                      border: Border.all(color: atl.frost, width: 5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFAEB2FF).withValues(alpha: 0.4 + 0.25 * t),
                          blurRadius: 18 + 8 * t,
                          offset: const Offset(0, 8),
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
