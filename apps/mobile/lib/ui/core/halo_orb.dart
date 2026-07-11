import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'atl_theme.dart';

/// Visual states of the Halo orb, mapped from the real voice pipeline.
enum HaloState { idle, listening, thinking, speaking }

/// The signature pearlescent "Halo" orb. A slowly-rotating iridescent sphere
/// with a soft outer glow that breathes, plus per-state overlays:
/// - listening → expanding accent rings,
/// - thinking  → a rotating conic arc,
/// - speaking  → an audio-style equalizer.
class HaloOrb extends StatefulWidget {
  const HaloOrb({super.key, required this.state, this.size = 200});

  final HaloState state;
  final double size;

  @override
  State<HaloOrb> createState() => _HaloOrbState();
}

class _HaloOrbState extends State<HaloOrb> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 15))
        ..repeat();
  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat(reverse: true);
  late final AnimationController _rings =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();
  late final AnimationController _think =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat();
  late final AnimationController _speak =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    _rings.dispose();
    _think.dispose();
    _speak.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final glow = s * 1.4;
    return SizedBox(
      width: glow,
      height: glow,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer breathing glow.
          AnimatedBuilder(
            animation: _breathe,
            builder: (_, _) {
              final t = _breathe.value;
              return Opacity(
                opacity: 0.92 + 0.08 * t,
                child: Transform.scale(
                  scale: 1.0 + 0.06 * t,
                  child: Container(
                    width: glow,
                    height: glow,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color(0x80AEB2FF),
                          Color(0x4D8FE9FF),
                          Color(0x2EF4A9D6),
                          Color(0x00000000),
                        ],
                        stops: [0.0, 0.38, 0.56, 0.72],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Listening rings.
          if (widget.state == HaloState.listening) ...[
            _ExpandingRing(controller: _rings, size: s, color: context.atl.accent),
            _ExpandingRing(
              controller: _rings,
              size: s,
              color: AtlColors.halo1,
              phase: 0.5,
            ),
          ],

          // Thinking arc.
          if (widget.state == HaloState.thinking)
            AnimatedBuilder(
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
                  if (widget.state == HaloState.speaking)
                    Center(child: _Equalizer(controller: _speak)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandingRing extends StatelessWidget {
  const _ExpandingRing({
    required this.controller,
    required this.size,
    required this.color,
    this.phase = 0.0,
  });

  final AnimationController controller;
  final double size;
  final Color color;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final t = (controller.value + phase) % 1.0;
        final scale = 0.6 + t * 1.4; // .6 → 2.0
        return Opacity(
          opacity: (0.5 * (1 - t)).clamp(0.0, 0.5),
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
    );
  }
}

class _Equalizer extends StatelessWidget {
  const _Equalizer({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    const heights = [26.0, 44.0, 20.0, 34.0];
    const delays = [0.0, 0.1, 0.2, 0.15];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(heights.length, (i) {
        return AnimatedBuilder(
          animation: controller,
          builder: (_, _) {
            final t = (controller.value + delays[i]) % 1.0;
            final scale = 0.3 + 0.7 * (0.5 - (t - 0.5).abs()) * 2;
            return Container(
              width: 4,
              height: heights[i] * scale,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A5A),
                borderRadius: BorderRadius.circular(3),
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
