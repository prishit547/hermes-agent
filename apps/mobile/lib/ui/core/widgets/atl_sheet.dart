import 'dart:ui';

import 'package:flutter/material.dart';

import '../atl_theme.dart';
import '../atl_tokens.dart';

/// Shows the app's standard frosted bottom sheet: rounded top, a grabber
/// handle, an optional title, safe-area padding, and a blurred scrim. Replaces
/// the ad-hoc `showModalBottomSheet` recipes scattered across ~5 screens so the
/// dismiss affordance and chrome are identical everywhere.
Future<T?> showAtlSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => AtlSheet(title: title, child: builder(ctx)),
  );
}

/// The sheet chrome itself (also usable directly if you need custom presentation).
class AtlSheet extends StatelessWidget {
  const AtlSheet({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AtlRadius.lg)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: atl.frost,
            border: Border(top: BorderSide(color: atl.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AtlSpace.gutter, AtlSpace.md, AtlSpace.gutter, AtlSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Grabber.
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: atl.homeInd,
                        borderRadius: BorderRadius.circular(AtlRadius.pill),
                      ),
                    ),
                  ),
                  if (title != null) ...[
                    const SizedBox(height: AtlSpace.md),
                    Text(title!,
                        textAlign: TextAlign.center,
                        style: AtlType.heading(color: atl.text)),
                  ],
                  const SizedBox(height: AtlSpace.lg),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
