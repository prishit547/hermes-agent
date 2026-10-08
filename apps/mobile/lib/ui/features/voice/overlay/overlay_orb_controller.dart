import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../../core/halo_orb.dart';

/// Logical size of the floating orb's content box (orb glow + caption). The
/// overlay engine renders at the device pixel ratio, so the native window must
/// be sized in *pixels* = these logical dimensions × dpr — otherwise the orb
/// (which is ~[kOverlayOrbSize]×dpr px wide) overflows a too-small window and
/// gets clipped ("only half showing").
const double kOverlayLogicalWidth = 176;
const double kOverlayLogicalHeight = 168;

/// Logical diameter of the orb inside the floating overlay.
const double kOverlayOrbSize = 60;

/// Wire-format keys for the state bridged to the overlay isolate. The overlay
/// runs in a separate Flutter engine, so the only link is a JSON message
/// channel ([FlutterOverlayWindow.shareData] / [overlayListener]).
class OverlayMsg {
  static const state = 's';
  static const label = 'l';
  static const amplitude = 'a';

  /// Sentinel the overlay sends back when the orb is tapped.
  static const tap = 'tap';
}

/// Main-isolate controller for the Android floating orb.
///
/// Owns the draw-over-apps window lifecycle and pushes live voice state to it.
/// A no-op on non-Android platforms (iOS can't host a true floating window; it
/// uses a Live Activity instead — see the iOS runner). Instances are cheap;
/// create one alongside the voice view-model.
class OverlayOrbController {
  OverlayOrbController();

  bool _listening = false;

  /// Whether a floating overlay is even possible on this platform.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// True while the overlay window is currently shown.
  Future<bool> get isActive async {
    if (!isSupported) return false;
    return FlutterOverlayWindow.isActive();
  }

  /// Whether "display over other apps" has been granted.
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return FlutterOverlayWindow.isPermissionGranted();
  }

  /// Ask the OS for the overlay permission. Returns the granted state.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    if (await FlutterOverlayWindow.isPermissionGranted()) return true;
    return (await FlutterOverlayWindow.requestPermission()) ?? false;
  }

  /// Show the floating orb. [onTap] fires when the user taps it in the overlay
  /// (wire it to `VoiceViewModel.tapOrb`). Requires permission — caller should
  /// have primed it. Safe to call when already showing.
  Future<void> show({required VoidCallback onTap}) async {
    if (!isSupported) return;
    if (!await hasPermission()) return;
    if (!await FlutterOverlayWindow.isActive()) {
      // showOverlay sizes are in physical pixels; convert from our logical box.
      final dpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
          3.0;
      await FlutterOverlayWindow.showOverlay(
        height: (kOverlayLogicalHeight * dpr).ceil(),
        width: (kOverlayLogicalWidth * dpr).ceil(),
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        overlayTitle: 'Atlantic',
        overlayContent: 'Tap the orb to talk',
      );
    }
    _listen(onTap);
  }

  void _listen(VoidCallback onTap) {
    if (_listening) return;
    _listening = true;
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event == OverlayMsg.tap) onTap();
    });
  }

  /// Push the current voice state to the overlay orb.
  Future<void> pushState({
    required HaloState state,
    required String label,
    required double amplitude,
  }) async {
    if (!isSupported) return;
    await FlutterOverlayWindow.shareData({
      OverlayMsg.state: state.index,
      OverlayMsg.label: label,
      OverlayMsg.amplitude: amplitude,
    });
  }

  /// Tear the overlay down.
  Future<void> hide() async {
    if (!isSupported) return;
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }
}
