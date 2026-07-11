import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the Atlantic / Halo design, carried as a [ThemeExtension]
/// so widgets read `Theme.of(context).extension<AtlColors>()!` and get the
/// right value for the active (dark/light) theme. Values mirror the CSS custom
/// properties in the source prototype 1:1.
@immutable
class AtlColors extends ThemeExtension<AtlColors> {
  const AtlColors({
    required this.appBg,
    required this.surface,
    required this.elevated,
    required this.surface2,
    required this.hairline,
    required this.divider,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
    required this.frost,
    required this.navInactive,
    required this.homeInd,
    required this.fieldBorder,
    required this.userBubble,
    required this.userInk,
    required this.cardShadow,
  });

  /// Radial app background (a gradient in the source).
  final Gradient appBg;
  final Color surface;
  final Color elevated;
  final Color surface2;
  final Color hairline;
  final Color divider;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentSoft;
  final Color accentInk;
  final Color frost;
  final Color navInactive;
  final Color homeInd;
  final Color fieldBorder;

  /// User chat bubble — a gradient in dark, a flat color in light.
  final Gradient userBubble;
  final Color userInk;
  final List<BoxShadow> cardShadow;

  /// The signature Halo orb gradient stops (cyan → lilac → pink), theme-agnostic.
  static const halo1 = Color(0xFF8FE9FF);
  static const halo2 = Color(0xFFB8A9FF);
  static const halo3 = Color(0xFFF4A9D6);
  static const accentThinking = Color(0xFFAEB2FF);
  static const eventPink = Color(0xFFF4A9D6);
  static const eventGold = Color(0xFFE7C9A0);
  static const eventBlue = Color(0xFF8FE9FF);
  static const positive = Color(0xFF25C9A5);
  static const danger = Color(0xFFFF6B75);

  static const dark = AtlColors(
    appBg: RadialGradient(
      center: Alignment(0, -1.12),
      radius: 1.2,
      colors: [Color(0xFF15141F), Color(0xFF08080C)],
      stops: [0.0, 0.55],
    ),
    surface: Color(0xFF12111A),
    elevated: Color(0xFF1A1922),
    surface2: Color(0xFF1A1922),
    hairline: Color(0x14FFFFFF),
    divider: Color(0x0FFFFFFF),
    text: Color(0xFFF1F1F4),
    text2: Color(0xFF9B9BA8),
    text3: Color(0xFF61616C),
    accent: Color(0xFFAEB2FF),
    accentSoft: Color(0x26AEB2FF),
    accentInk: Color(0xFF0A0A14),
    frost: Color(0xC708080C),
    navInactive: Color(0xFF61616C),
    homeInd: Color(0xFF5A5A63),
    fieldBorder: Color(0x14FFFFFF),
    userBubble: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFAEB2FF), Color(0xFFC9B8FF)],
    ),
    userInk: Color(0xFF111018),
    cardShadow: [],
  );

  static const light = AtlColors(
    appBg: RadialGradient(
      center: Alignment(0, -1.12),
      radius: 1.2,
      colors: [Color(0xFFFFFFFF), Color(0xFFF0F1F6)],
      stops: [0.0, 0.58],
    ),
    surface: Color(0xFFFFFFFF),
    elevated: Color(0xFFFFFFFF),
    surface2: Color(0xFFF4F4F9),
    hairline: Color(0xFFECECF2),
    divider: Color(0xFFF0F0F5),
    text: Color(0xFF15151C),
    text2: Color(0xFF5C5C67),
    text3: Color(0xFF9A9AA6),
    accent: Color(0xFF5D5FEC),
    accentSoft: Color(0x1A5D5FEC),
    accentInk: Color(0xFFFFFFFF),
    frost: Color(0xD1F8F8FC),
    navInactive: Color(0xFF9A9AA6),
    homeInd: Color(0xFFC7C7D0),
    fieldBorder: Color(0xFFE6E6EE),
    userBubble: LinearGradient(colors: [Color(0xFF5D5FEC), Color(0xFF5D5FEC)]),
    userInk: Color(0xFFFFFFFF),
    cardShadow: [
      BoxShadow(
        color: Color(0x1F1E1E3C),
        blurRadius: 24,
        offset: Offset(0, 8),
        spreadRadius: -10,
      ),
    ],
  );

  /// The pearlescent orb sphere gradient (shared by both themes).
  static const haloSphere = SweepGradient(
    colors: [halo1, halo2, halo3, halo1],
  );

  @override
  AtlColors copyWith() => this;

  @override
  AtlColors lerp(ThemeExtension<AtlColors>? other, double t) {
    if (other is! AtlColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// Convenience accessor.
extension AtlContext on BuildContext {
  AtlColors get atl => Theme.of(this).extension<AtlColors>()!;
}

/// Builds the [ThemeData] for a given brightness, attaching [AtlColors] and the
/// three brand typefaces via google_fonts.
ThemeData buildAtlTheme(Brightness brightness) {
  final atl = brightness == Brightness.dark ? AtlColors.dark : AtlColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xFF08080C)
        : const Color(0xFFF6F6FA),
    colorScheme: ColorScheme.fromSeed(
      seedColor: atl.accent,
      brightness: brightness,
    ),
  );
  return base.copyWith(
    extensions: [atl],
    textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme).apply(
      bodyColor: atl.text,
      displayColor: atl.text,
    ),
  );
}

/// Instrument Serif — used for large display/greeting text and italic accents.
TextStyle atlSerif({
  required double size,
  Color? color,
  FontStyle style = FontStyle.normal,
  double height = 1.1,
}) =>
    GoogleFonts.instrumentSerif(
      fontSize: size,
      color: color,
      fontStyle: style,
      height: height,
    );

/// JetBrains Mono — used for times, dates, and figures.
TextStyle atlMono({
  required double size,
  Color? color,
  FontWeight weight = FontWeight.w500,
}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, color: color, fontWeight: weight);

/// Hanken Grotesk — the body/UI face.
TextStyle atlSans({
  required double size,
  Color? color,
  FontWeight weight = FontWeight.w400,
  double? height,
  double? letterSpacing,
  TextDecoration? decoration,
}) =>
    GoogleFonts.hankenGrotesk(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    );
