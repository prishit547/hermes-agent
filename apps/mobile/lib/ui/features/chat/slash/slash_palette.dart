import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/animations.dart';
import '../../../core/atl_theme.dart';
import 'slash_commands.dart';

/// The inline command menu shown above the chat input while the user is typing
/// a `/` command. Tapping a row selects it via [onSelect].
class SlashPalette extends StatelessWidget {
  const SlashPalette({super.key, required this.commands, required this.onSelect});

  final List<SlashCommand> commands;
  final void Function(SlashCommand) onSelect;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    if (commands.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      constraints: const BoxConstraints(maxHeight: 260),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: atl.frost,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: atl.hairline),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: commands.length,
              itemBuilder: (_, i) {
                final c = commands[i];
                return Pressable(
                  onTap: () => onSelect(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(c.icon, size: 18, color: atl.accent),
                        const SizedBox(width: 12),
                        Text('/${c.name}',
                            style: atlMono(size: 14, color: atl.text)),
                        if (c.argHint != null) ...[
                          const SizedBox(width: 6),
                          Text(c.argHint!, style: atlMono(size: 12, color: atl.text3)),
                        ],
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            c.description,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: atlSans(size: 12, color: atl.text3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
