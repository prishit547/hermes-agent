/// Design tokens for the Atlantic / Halo system.
///
/// These are the single source of truth for spacing, corner radii, and motion.
/// Screens should read from here instead of hardcoding `SizedBox(height: 17)`,
/// `BorderRadius.circular(14)`, or `Duration(milliseconds: 300)` inline — that
/// ad-hoc drift is what makes the app feel slightly off from itself.
///
/// Colour and shadow tokens live in [AtlColors] (`atl_theme.dart`) because they
/// are theme-dependent; everything here is theme-agnostic.
library;

import 'package:flutter/widgets.dart';

/// Spacing scale on a 4/8dp rhythm. Use for gaps, padding, and insets.
///
/// ```dart
/// const SizedBox(height: AtlSpace.lg);
/// padding: const EdgeInsets.all(AtlSpace.md);
/// ```
abstract final class AtlSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Standard horizontal screen gutter.
  static const double gutter = 18;
}

/// Corner-radius scale. Collapses the historical 10–22 drift to four steps.
abstract final class AtlRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;

  /// Fully rounded (pills, circular buttons); clamp with `min(h/2, pill)`.
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}

/// Motion tokens — one shared rhythm for the whole app.
///
/// Durations follow the platform guidance of 120–340ms for UI transitions
/// (micro-interactions fast, screen/state changes base–slow). Exit motion
/// should be quicker than enter, hence [exit].
abstract final class AtlMotion {
  /// Micro-interactions: press, ripple, toggle. ~120ms.
  static const Duration fast = Duration(milliseconds: 120);

  /// Default state/content transitions (crossfades, switches). ~250ms.
  static const Duration base = Duration(milliseconds: 250);

  /// Larger spatial transitions (screen/tab changes). ~340ms.
  static const Duration slow = Duration(milliseconds: 340);

  /// Exit transitions — snappier than the matching enter (~70%).
  static const Duration exit = Duration(milliseconds: 180);

  /// Enter easing: decelerate into place.
  static const Curve enterCurve = Curves.easeOutCubic;

  /// Exit easing: accelerate away.
  static const Curve exitCurve = Curves.easeIn;

  /// Springy emphasis for the orb and tactile press-backs.
  static const Curve spring = Curves.easeOutBack;

  /// Standard symmetric curve for value-driven animations.
  static const Curve standard = Curves.easeInOut;
}
