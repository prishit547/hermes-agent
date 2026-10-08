import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/atl_theme.dart';
import '../../core/halo_orb.dart';
import '../../../data/services/audio_service.dart';
import '../shell/shell_controller.dart';
import 'voice_view_model.dart';

/// Full-screen Halo voice experience. The orb reflects the real pipeline state;
/// tapping it advances the push-to-talk state machine.
class VoiceOverlay extends StatefulWidget {
  const VoiceOverlay({super.key});

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay>
    with WidgetsBindingObserver {
  final _stopwatch = Stopwatch()..start();
  Timer? _timer;
  late final VoiceViewModel _vm;

  /// Set when we're handing the session off to the floating orb, so [dispose]
  /// keeps the voice pipeline alive instead of tearing it down.
  bool _keepAliveForOverlay = false;

  @override
  void initState() {
    super.initState();
    _vm = context.read<VoiceViewModel>();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    // Connect the realtime voice socket and start the hands-free loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _vm.begin();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    // Stop mic, playback, socket and the native CallKit/telecom call — unless
    // the floating orb is taking over the session.
    if (!_keepAliveForOverlay) _vm.reset();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _handleBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      // Back in the app — the full-screen orb takes over again.
      _vm.hideOverlay();
    }
  }

  /// On backgrounding: if the floating orb is available and already permitted,
  /// keep the session alive and follow the user with the orb. Otherwise fall
  /// back to the previous behaviour and end the session.
  Future<void> _handleBackgrounded() async {
    if (_vm.overlayAvailable && await _vm.hasOverlayPermission()) {
      await _vm.showOverlay();
    } else if (mounted) {
      context.read<ShellController>().closeVoice();
    }
  }

  /// Explicit "minimize to floating orb" from the top bar: prime the permission
  /// if needed, show the orb, and drop the full-screen surface while the session
  /// continues in the background.
  Future<void> _minimizeToOrb() async {
    final granted = await _vm.requestOverlayPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Enable “Display over other apps” to use the floating orb.'),
        ));
      }
      return;
    }
    await _vm.showOverlay();
    _keepAliveForOverlay = true;
    if (mounted) context.read<ShellController>().closeVoice();
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
                        Text(
                          'Hands-free',
                          style: atlSans(
                            size: 12,
                            color: atl.text2,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(_elapsed, style: atlMono(size: 14, color: atl.text3)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (vm.overlayAvailable) ...[
                        _circleBtn(
                          atl,
                          Icons.picture_in_picture_alt,
                          _minimizeToOrb,
                        ),
                        const SizedBox(width: 10),
                      ],
                      _circleBtn(atl, Icons.close, () => shell.closeVoice()),
                    ],
                  ),
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
                    builder: (_, s, child) =>
                        Transform.scale(scale: s, child: child),
                    child: GestureDetector(
                      onTap: vm.tapOrb,
                      child: HaloOrb(
                          state: vm.state, size: 200, amplitude: vm.level),
                    ),
                  ),
                  const SizedBox(height: 38),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 34),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            vm.label,
                            key: ValueKey(vm.label),
                            textAlign: TextAlign.center,
                            style: atlSerif(
                              size: 30,
                              color: atl.text,
                              style: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            vm.transcript,
                            key: ValueKey(vm.transcript),
                            textAlign: TextAlign.center,
                            style: atlSans(
                              size: 19,
                              color: atl.text2,
                              height: 1.5,
                            ),
                          ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 17,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: atl.frost,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: atl.hairline),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _softBtn(
                              atl,
                              vm.muted ? Icons.mic_off : Icons.mic_none,
                              vm.toggleMute,
                              color: vm.muted ? AtlColors.danger : null,
                            ),
                            _softBtn(
                              atl,
                              Icons.keyboard_alt_outlined,
                              () => shell.go(AtlTab.chat),
                            ),
                            _endBtn(() => shell.closeVoice()),
                            _accentBtn(
                              atl,
                              _outputIcon(vm.audioOutput),
                              vm.cycleAudioOutput,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Mute · audio route · red to end',
                    style: atlSans(size: 11, color: atl.text3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(AtlColors atl, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: atl.surface2,
          ),
          child: Icon(icon, size: 16, color: atl.text2),
        ),
      );

  Widget _softBtn(
    AtlColors atl,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(shape: BoxShape.circle, color: atl.surface2),
      child: Icon(icon, size: 21, color: color ?? atl.text),
    ),
  );

  IconData _outputIcon(AudioOutput output) {
    switch (output) {
      case AudioOutput.bluetooth:
        return Icons.bluetooth;
      case AudioOutput.earpiece:
        return Icons.hearing;
      case AudioOutput.speaker:
        return Icons.volume_up_outlined;
    }
  }

  Widget _accentBtn(AtlColors atl, IconData icon, VoidCallback onTap) =>
      GestureDetector(
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
