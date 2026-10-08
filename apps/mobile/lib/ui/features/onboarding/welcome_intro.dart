import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/atl_theme.dart';
import '../../core/halo_orb.dart';
import '../../core/widgets/widgets.dart';

/// First-run welcome + permission priming, shown before the connection form.
///
/// It introduces the Halo orb and *primes* the microphone and notification
/// permissions — explaining why each is needed before the OS prompt fires,
/// which is the platform-recommended pattern and far better than the app's old
/// cold-open straight into a settings form. Calls [onDone] when finished.
class WelcomeIntro extends StatefulWidget {
  const WelcomeIntro({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<WelcomeIntro> createState() => _WelcomeIntroState();
}

class _WelcomeIntroState extends State<WelcomeIntro> {
  final _pager = PageController();
  int _page = 0;
  bool _micGranted = false;
  bool _notifGranted = false;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _requestMic() async {
    final status = await Permission.microphone.request();
    if (mounted) setState(() => _micGranted = status.isGranted);
  }

  Future<void> _requestNotifications() async {
    final status = await Permission.notification.request();
    if (mounted) setState(() => _notifGranted = status.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: atl.appBg),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pager,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [_intro(atl), _permissions(atl)],
                ),
              ),
              _footer(atl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro(AtlColors atl) {
    return Padding(
      padding: const EdgeInsets.all(AtlSpace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const HaloOrb(state: HaloState.idle, size: 160),
          const SizedBox(height: AtlSpace.xxl),
          Text('Meet Atlantic',
              textAlign: TextAlign.center, style: AtlType.display(color: atl.text)),
          const SizedBox(height: AtlSpace.md),
          Text(
            'Your voice-first assistant. Tap the orb to talk hands-free — it '
            'listens, thinks, and speaks back.',
            textAlign: TextAlign.center,
            style: AtlType.body(color: atl.text2),
          ),
        ],
      ),
    );
  }

  Widget _permissions(AtlColors atl) {
    return Padding(
      padding: const EdgeInsets.all(AtlSpace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enable the essentials',
              textAlign: TextAlign.center, style: AtlType.title(color: atl.text)),
          const SizedBox(height: AtlSpace.sm),
          Text(
            'Atlantic works best with these. You can change them anytime in '
            'system settings.',
            textAlign: TextAlign.center,
            style: AtlType.caption(color: atl.text2),
          ),
          const SizedBox(height: AtlSpace.xl),
          _permissionTile(
            atl,
            icon: Icons.mic_none,
            title: 'Microphone',
            subtitle: 'For hands-free voice conversations.',
            granted: _micGranted,
            onAllow: _requestMic,
          ),
          const SizedBox(height: AtlSpace.md),
          _permissionTile(
            atl,
            icon: Icons.notifications_none,
            title: 'Notifications',
            subtitle: 'For reminders, briefings, and alerts.',
            granted: _notifGranted,
            onAllow: _requestNotifications,
          ),
          const SizedBox(height: AtlSpace.md),
          Text(
            'On Android you can also enable a floating orb '
            '(“Display over other apps”) later to talk while using other apps.',
            textAlign: TextAlign.center,
            style: AtlType.caption(color: atl.text3),
          ),
        ],
      ),
    );
  }

  Widget _permissionTile(
    AtlColors atl, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onAllow,
  }) {
    return AtlCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: atl.accentSoft,
              borderRadius: AtlRadius.smAll,
            ),
            child: Icon(icon, size: 20, color: atl.accent),
          ),
          const SizedBox(width: AtlSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AtlType.body(color: atl.text, weight: FontWeight.w600)),
                Text(subtitle, style: AtlType.caption(color: atl.text2)),
              ],
            ),
          ),
          const SizedBox(width: AtlSpace.sm),
          if (granted)
            Icon(Icons.check_circle, color: AtlColors.positive, size: 26)
          else
            TextButton(
              onPressed: onAllow,
              style: TextButton.styleFrom(foregroundColor: atl.accent),
              child: const Text('Allow'),
            ),
        ],
      ),
    );
  }

  Widget _footer(AtlColors atl) {
    final isLast = _page == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AtlSpace.xl, 0, AtlSpace.xl, AtlSpace.xl),
      child: Column(
        children: [
          // Page dots.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(2, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: AtlMotion.base,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? atl.accent : atl.hairline,
                  borderRadius: BorderRadius.circular(AtlRadius.pill),
                ),
              );
            }),
          ),
          const SizedBox(height: AtlSpace.lg),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () {
                if (isLast) {
                  widget.onDone();
                } else {
                  _pager.nextPage(
                      duration: AtlMotion.base, curve: AtlMotion.enterCurve);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: atl.accent,
                foregroundColor: atl.accentInk,
                shape: RoundedRectangleBorder(borderRadius: AtlRadius.mdAll),
              ),
              child: Text(isLast ? 'Get started' : 'Next',
                  style: AtlType.body(color: atl.accentInk, weight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
