import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/atl_theme.dart';
import '../../core/halo_orb.dart';
import '../shell/shell_controller.dart';
import 'voice_view_model.dart';

/// Full-screen Halo voice experience. The orb reflects the real pipeline state;
/// tapping it advances the push-to-talk state machine.
class VoiceOverlay extends StatefulWidget {
  const VoiceOverlay({super.key});

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay> {
  final _stopwatch = Stopwatch()..start();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    // Connect the realtime voice socket and start the hands-free loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<VoiceViewModel>().begin();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    context.read<VoiceViewModel>().reset();
    super.dispose();
  }

  String get _elapsed {
    final s = _stopwatch.elapsed.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<VoiceViewModel>();
    final shell = context.read<ShellController>();

    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
                    decoration: BoxDecoration(
                      color: atl.surface2,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: atl.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AtlColors.positive,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text('Hands-free',
                            style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  Text(_elapsed, style: atlMono(size: 14, color: atl.text3)),
                  _circleBtn(atl, Icons.close, () => shell.closeVoice()),
                ],
              ),
            ),

            // Orb + captions
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.85, end: 1.0),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutBack,
                    builder: (_, s, child) => Transform.scale(scale: s, child: child),
                    child: GestureDetector(
                      onTap: vm.tapOrb,
                      child: HaloOrb(state: vm.state, size: 200),
                    ),
                  ),
                  const SizedBox(height: 38),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 34),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(vm.label,
                              key: ValueKey(vm.label),
                              textAlign: TextAlign.center,
                              style: atlSerif(
                                  size: 30, color: atl.text, style: FontStyle.italic)),
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(vm.transcript,
                              key: ValueKey(vm.transcript),
                              textAlign: TextAlign.center,
                              style: atlSans(size: 19, color: atl.text2, height: 1.5)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Control bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
                        decoration: BoxDecoration(
                          color: atl.frost,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: atl.hairline),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _softBtn(atl, Icons.mic_none, vm.tapOrb),
                            _softBtn(atl, Icons.keyboard_alt_outlined,
                                () => shell.go(AtlTab.chat)),
                            _endBtn(() => shell.closeVoice()),
                            _accentBtn(atl, Icons.volume_up_outlined, () {}),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Tap the orb to talk · red to end',
                      style: atlSans(size: 11, color: atl.text3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(AtlColors atl, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(shape: BoxShape.circle, color: atl.surface2),
          child: Icon(icon, size: 16, color: atl.text2),
        ),
      );

  Widget _softBtn(AtlColors atl, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(shape: BoxShape.circle, color: atl.surface2),
          child: Icon(icon, size: 21, color: atl.text),
        ),
      );

  Widget _accentBtn(AtlColors atl, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: atl.accentSoft,
            border: Border.all(color: atl.accent),
          ),
          child: Icon(icon, size: 21, color: atl.accent),
        ),
      );

  Widget _endBtn(VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AtlColors.danger,
            boxShadow: const [
              BoxShadow(
                color: Color(0x99FF6B75),
                blurRadius: 26,
                offset: Offset(0, 10),
                spreadRadius: -6,
              ),
            ],
          ),
          child: const Icon(Icons.call_end, size: 24, color: Colors.white),
        ),
      );
}
