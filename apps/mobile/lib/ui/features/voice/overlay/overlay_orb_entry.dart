import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../../core/atl_theme.dart';
import '../../../core/halo_orb.dart';
import 'overlay_orb_controller.dart';

/// The root widget rendered inside the Android floating-orb overlay engine.
///
/// `flutter_overlay_window` spins up a *separate* Flutter engine and runs the
/// top-level `overlayMain` entrypoint (defined in `main.dart`, where the VM can
/// resolve it), which mounts this. It shares no state with the main isolate
/// except JSON messages over the overlay channel.
class OverlayOrbApp extends StatelessWidget {
  const OverlayOrbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // The orb reads `context.atl` and the scaffold background, so it needs the
      // full Atlantic theme even in the overlay engine.
      theme: buildAtlTheme(Brightness.dark),
      home: const Scaffold(
        backgroundColor: Colors.transparent,
        body: _OverlayOrb(),
      ),
    );
  }
}

class _OverlayOrb extends StatefulWidget {
  const _OverlayOrb();

  @override
  State<_OverlayOrb> createState() => _OverlayOrbState();
}

class _OverlayOrbState extends State<_OverlayOrb> {
  HaloState _state = HaloState.idle;
  String _label = 'Tap to talk';
  final ValueNotifier<double> _amp = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen(_onMessage);
  }

  void _onMessage(dynamic message) {
    if (message is! Map) return;
    final stateIdx = message[OverlayMsg.state];
    final label = message[OverlayMsg.label];
    final amp = message[OverlayMsg.amplitude];
    setState(() {
      if (stateIdx is int &&
          stateIdx >= 0 &&
          stateIdx < HaloState.values.length) {
        _state = HaloState.values[stateIdx];
      }
      if (label is String) _label = label;
    });
    if (amp is num) _amp.value = amp.toDouble().clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _amp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    // Match the native window's logical box exactly and center the orb inside,
    // so the glow never overflows and gets clipped.
    return SizedBox(
      width: kOverlayLogicalWidth,
      height: kOverlayLogicalHeight,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // A compact caption bubble above the orb echoing the current label.
            if (_label.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                constraints: const BoxConstraints(maxWidth: kOverlayLogicalWidth - 12),
                decoration: BoxDecoration(
                  color: atl.frost,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: atl.hairline),
                ),
                child: Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: atlSans(size: 10.5, color: atl.text, weight: FontWeight.w600),
                ),
              ),
            GestureDetector(
              onTap: () => FlutterOverlayWindow.shareData(OverlayMsg.tap),
              child: HaloOrb(
                  state: _state, size: kOverlayOrbSize, amplitude: _amp),
            ),
          ],
        ),
      ),
    );
  }
}
