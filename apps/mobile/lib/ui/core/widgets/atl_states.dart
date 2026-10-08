import 'package:flutter/material.dart';

import '../atl_theme.dart';
import '../atl_tokens.dart';
import 'atl_card.dart';

/// Standard empty-state block: a muted icon, a title, supporting copy, and an
/// optional call-to-action. Generalises MCP's `_emptyState` (the quality bar)
/// so every screen's "nothing here yet" looks the same.
class AtlEmptyState extends StatelessWidget {
  const AtlEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AtlSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: atl.text3),
            const SizedBox(height: AtlSpace.md),
            Text(title, textAlign: TextAlign.center, style: AtlType.heading(color: atl.text)),
            if (message != null) ...[
              const SizedBox(height: AtlSpace.xs + 2),
              Text(message!,
                  textAlign: TextAlign.center, style: AtlType.caption(color: atl.text3)),
            ],
            if (action != null) ...[
              const SizedBox(height: AtlSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard error-state block with a built-in retry affordance. Prefer this
/// over transient snackbars for load failures the user needs to act on.
class AtlErrorState extends StatelessWidget {
  const AtlErrorState({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.icon = Icons.cloud_off,
    this.onRetry,
  });

  final String message;
  final String title;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AtlSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: atl.text3),
            const SizedBox(height: AtlSpace.md),
            Text(title, textAlign: TextAlign.center, style: AtlType.heading(color: atl.text)),
            const SizedBox(height: AtlSpace.xs + 2),
            Text(message,
                textAlign: TextAlign.center, style: AtlType.caption(color: atl.text3)),
            if (onRetry != null) ...[
              const SizedBox(height: AtlSpace.lg),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: TextButton.styleFrom(foregroundColor: atl.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Uppercase eyebrow label that heads a section, with an optional trailing
/// widget (e.g. an "Add" button or a count).
class AtlSectionLabel extends StatelessWidget {
  const AtlSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return Padding(
      padding: const EdgeInsets.only(bottom: AtlSpace.sm, left: AtlSpace.xs),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: AtlType.eyebrow(color: atl.text3)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// "Connect X" prompt card, unifying the inline banners for unconfigured
/// services (email not set up, Google Calendar not linked, music unavailable).
class AtlConnectBanner extends StatelessWidget {
  const AtlConnectBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return AtlCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
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
                const SizedBox(height: AtlSpace.xs / 2),
                Text(message, style: AtlType.caption(color: atl.text2)),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AtlSpace.sm),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: atl.accent,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
