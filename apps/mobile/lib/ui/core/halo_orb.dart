import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'atl_theme.dart';
import 'atl_tokens.dart';

/// Visual states of the Halo orb, mapped from the real voice pipeline.
enum HaloState { idle, listening, thinking, speaking, error }

/// The signature pearlescent "Halo" orb. A slowly-rotating iridescent sphere
/// with a soft outer glow that breathes, plus per-state overlays:
/// - listening → expanding accent rings that **react to live mic loudness**,
/// - thinking  → a rotating conic arc,
/// - speaking  → an audio-style equalizer,
/// - error     → a brief danger-tinted pulse.
///
/// Pass [amplitude] (a `ValueListenable<double>` in 0..1, typically the voice
/// view-model's mic level) to drive the listening reaction. The orb low-pass
/// smooths it internally so the motion reads organic rather than jittery, and
/// consumes it via a [ValueListenableBuilder] so amplitude ticks don't rebuild
/// the surrounding UI.
///
/// Only [_spin] and [_breathe] run continuously; the per-state controllers are
/// started and stopped as the state changes to save battery. When the platform
/// requests reduced motion the orb falls back to a static, dimmed sphere.
class HaloOrb extends StatefulWidget {
  const HaloOrb({
    super.key,
    required this.state,
    this.size = 200,
    this.amplitude,
  });

  final HaloState state;
  final double size;
  final ValueListenable<double>? amplitude;

  @override
  State<HaloOrb> createState() => _HaloOrbState();
}

class _HaloOrbState extends State<HaloOrb> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 15));
  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  late final AnimationController _rings =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _think =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  late final AnimationController _speak =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  /// Smoothed mic energy (0..1), advanced each frame off [_spin]'s ticks so we
  /// never spin up a dedicated ticker just for smoothing.
  final ValueNotifier<double> _energy = ValueNotifier(0);

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _spin.addListener(_advanceEnergy);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncControllers();
  }

  @override
  void didUpdateWidget(HaloOrb old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncControllers();
  }

  /// Continuously eases the smoothed [_energy] toward the current target so the
  /// reaction has weight instead of snapping between coarse 5 Hz amplitude ticks.
  ///
  /// While listening this tracks live mic loudness. While speaking — where no
  /// real TTS output envelope is available — it synthesizes a lively envelope
  /// from the equalizer + breathe controllers so the orb visibly "talks"
  /// (pulsing glow) instead of sitting inert.
  void _advanceEnergy() {
    double target;
    if (_reduceMotion) {
      target = 0.0;
    } else if (widget.state == HaloState.listening) {
      target = (widget.amplitude?.value ?? 0).clamp(0.0, 1.0);
    } else if (widget.state == HaloState.speaking) {
      // Two out-of-phase triangle waves → an organic, speech-like cadence.
      final a = (0.5 - (_speak.value - 0.5).abs()) * 2; // 0..1 @ 600ms
      final b = (0.5 - (_breathe.value - 0.5).abs()) * 2; // 0..1 @ 6s
      target = (0.45 + 0.4 * a + 0.15 * b).clamp(0.0, 1.0);
    } else {
      target = 0.0;
    }
    final next = _energy.value + (target - _energy.value) * 0.22;
    if ((next - _energy.value).abs() > 0.0005) _energy.value = next;
  }

  /// Runs exactly the controllers the current state needs; stops the rest.
  void _syncControllers() {
    if (_reduceMotion) {
      for (final c in [_spin, _breathe, _rings, _think, _speak]) {
        c.stop();
      }
      return;
    }
    _repeat(_spin, on: true);
    _repeat(_breathe, on: true, reverse: true);
    _repeat(_rings, on: widget.state == HaloState.listening);
    _repeat(_think, on: widget.state == HaloState.thinking);
    _repeat(_speak, on: widget.state == HaloState.speaking, reverse: true);
    // Error gives the glow a single settling pulse via _breathe (already on).
  }

  void _repeat(AnimationController c, {required bool on, bool reverse = false}) {
    if (on) {
      if (!c.isAnimating) c.repeat(reverse: reverse);
    } else if (c.isAnimating) {
      c.stop();
      c.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.removeListener(_advanceEnergy);
    _spin.dispose();
    _breathe.dispose();
    _rings.dispose();
    _think.dispose();
    _speak.dispose();
    _energy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final glow = s * 1.4;
    final isError = widget.state == HaloState.error;
    final isIdle = widget.state == HaloState.idle;

    return SizedBox(
      width: glow,
      height: glow,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer breathing glow — reacts to mic energy while listening, dims
          // at idle, and shifts toward danger on error.
          AnimatedBuilder(
            animation: _breathe,
            builder: (_, _) => ValueListenableBuilder<double>(
              valueListenable: _energy,
              builder: (_, energy, _) {
                final t = _breathe.value;
                final base = isIdle ? 0.55 : 0.92;
                return Opacity(
                  opacity: (base + 0.08 * t + 0.25 * energy).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 1.0 + 0.06 * t + 0.12 * energy,
                    child: Container(
                      width: glow,
                      height: glow,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: isError
                              ? const [
                                  Color(0x80FF6B75),
                                  Color(0x33FF6B75),
                                  Color(0x00000000),
                                ]
                              : const [
                                  Color(0x80AEB2FF),
                                  Color(0x4D8FE9FF),
                                  Color(0x2EF4A9D6),
                                  Color(0x00000000),
                                ],
                          stops: isError
                              ? const [0.0, 0.5, 0.72]
                              : const [0.0, 0.38, 0.56, 0.72],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Per-state overlay behind the sphere, crossfaded on state change.
          AnimatedSwitcher(
            duration: AtlMotion.base,
            child: _behindOverlay(s),
          ),

          // The sphere.
          ClipOval(
            child: SizedBox(
              width: s,
              height: s,
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (_, _) => Transform.rotate(
                      angle: _spin.value * 2 * math.pi,
                      child: OverflowBox(
                        maxWidth: s * 1.44,
                        maxHeight: s * 1.44,
                        child: CustomPaint(
                          size: Size(s * 1.44, s * 1.44),
                          painter: _PearlPainter(),
                        ),
                      ),
                    ),
                  ),
                  // Inner shadow + highlight vignette for a glassy sphere.
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: Alignment(-0.35, -0.4),
                        radius: 1.1,
                        colors: [Color(0x8CFFFFFF), Color(0x00FFFFFF), Color(0x52788CC8)],
                        stops: [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                  // Idle dims the sphere slightly so "resting" reads distinctly
                  // from the live states.
                  if (isIdle)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x22000000),
                      ),
                    ),
                  if (widget.state == HaloState.speaking && !_reduceMotion)
                    Center(
                      child: _Equalizer(
                        controller: _speak,
                        scale: (s / 200).clamp(0.3, 1.2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The state-specific decoration drawn *behind* the sphere, keyed so the
  /// [AnimatedSwitcher] crossfades between states instead of snapping.
  Widget _behindOverlay(double s) {
    if (_reduceMotion) return const SizedBox.shrink(key: ValueKey('none'));
    switch (widget.state) {
      case HaloState.listening:
        return Stack(
          key: const ValueKey('listening'),
          alignment: Alignment.center,
          children: [
            _ExpandingRing(
                controller: _rings, size: s, color: context.atl.accent, energy: _energy),
            _ExpandingRing(
                controller: _rings,
                size: s,
                color: AtlColors.halo1,
                phase: 0.5,
                energy: _energy),
          ],
        );
      case HaloState.thinking:
        return AnimatedBuilder(
          key: const ValueKey('thinking'),
          animation: _think,
          builder: (_, _) => Transform.rotate(
            angle: _think.value * 2 * math.pi,
            child: Container(
              width: s * 1.12,
              height: s * 1.12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Color(0x008FE9FF),
                    AtlColors.halo1,
                    AtlColors.accentThinking,
                    Color(0x00AEB2FF),
                  ],
                  stops: [0.0, 0.35, 0.5, 0.65],
                ),
              ),
              child: Center(
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ),
            ),
          ),
        );
      case HaloState.error:
        return Container(
          key: const ValueKey('error'),
          width: s * 1.06,
          height: s * 1.06,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AtlColors.danger.withValues(alpha: 0.7), width: 2),
          ),
        );
      case HaloState.idle:
      case HaloState.speaking:
        return const SizedBox.shrink(key: ValueKey('none'));
    }
  }
}

class _ExpandingRing extends StatelessWidget {
  const _ExpandingRing({
    required this.controller,
    required this.size,
    required this.color,
    required this.energy,
    this.phase = 0.0,
  });

  final AnimationController controller;
  final double size;
  final Color color;
  final double phase;
  final ValueListenable<double> energy;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) => ValueListenableBuilder<double>(
        valueListenable: energy,
        builder: (_, e, _) {
          final t = (controller.value + phase) % 1.0;
          // Louder speech pushes the rings wider and brighter.
          final scale = 0.6 + t * (1.4 + 0.8 * e);
          return Opacity(
            opacity: ((0.35 + 0.5 * e) * (1 - t)).clamp(0.0, 0.6),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Equalizer extends StatelessWidget {
  const _Equalizer({required this.controller, this.scale = 1.0});
  final AnimationController controller;

  /// Scales the whole equalizer to the orb size (so it stays proportional on
  /// the small floating orb as well as the full-screen one).
  final double scale;

  @override
  Widget build(BuildContext context) {
    // Taller bars in a deep indigo read clearly against the light pearl orb.
    const heights = [30.0, 56.0, 40.0, 62.0, 34.0];
    const delays = [0.0, 0.12, 0.24, 0.08, 0.18];
    const barColor = Color(0xFF2E2D57);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(heights.length, (i) {
        return AnimatedBuilder(
          animation: controller,
          builder: (_, _) {
            final t = (controller.value + delays[i]) % 1.0;
            // Keep a visible floor (0.35) so the bars always read as "speaking".
            final h = 0.35 + 0.65 * (0.5 - (t - 0.5).abs()) * 2;
            return Container(
              width: 5 * scale,
              height: heights[i] * h * scale,
              margin: EdgeInsets.symmetric(horizontal: 2.5 * scale),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(4 * scale),
              ),
            );
          },
        );
      }),
    );
  }
}

/// Paints the layered pearlescent radial blobs that give the sphere its
/// iridescent, oil-slick look (approximating the source's stacked gradients).
class _PearlPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Base wash.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFD3E6FF),
    );
    void blob(double cx, double cy, double r, Color color) {
      final rect = Rect.fromCircle(center: Offset(w * cx, h * cy), radius: w * r);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    blob(0.40, 0.20, 0.44, AtlColors.halo2);
    blob(0.26, 0.44, 0.46, AtlColors.halo3);
    blob(0.74, 0.26, 0.48, AtlColors.halo1);
    blob(0.52, 0.58, 0.62, const Color(0xFFEAF3FF));
    blob(0.66, 0.72, 0.42, const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
