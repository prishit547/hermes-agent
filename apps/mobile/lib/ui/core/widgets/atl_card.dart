import 'package:flutter/material.dart';

import '../animations.dart';
import '../atl_theme.dart';
import '../atl_tokens.dart';

/// The canonical Atlantic surface card: [AtlColors.surface] fill, hairline
/// border, and the theme's resting shadow. Replaces the per-screen `_card()`
/// helpers that had drifted across radii (10–22) and paddings.
///
/// Pass [onTap] to make it a [Pressable] (press-scale feedback). Pass [gradient]
/// for the signature cyan→pink briefing/now-playing surfaces.
class AtlCard extends StatelessWidget {
  const AtlCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AtlSpace.lg),
    this.radius = AtlRadius.lg,
    this.gradient,
    this.onTap,
    this.elevated = false,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Gradient? gradient;
  final VoidCallback? onTap;

  /// Use the higher [AtlColors.elevatedShadow] tier (sheets, floating cards).
  final bool elevated;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? atl.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: atl.hairline) : null,
        boxShadow: elevated ? atl.elevatedShadow : atl.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, child: card);
  }
}
