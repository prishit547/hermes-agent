import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/system_repository.dart';
import '../../../core/atl_theme.dart';
import '../../mcp/mcp_screen.dart';
import '../../reminders/reminders_screen.dart';
import '../../settings/model_switcher.dart';
import '../view_models/chat_view_model.dart';
import '../views/session_drawer.dart';

/// One entry in the `/` command palette.
class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    required this.icon,
    this.aliases = const [],
    this.argHint,
    required this.run,
  });

  final String name;
  final String description;
  final IconData icon;
  final List<String> aliases;

  /// When set, the command takes an argument; selecting it pre-fills the input
  /// as `"/name "` instead of running immediately.
  final String? argHint;

  /// Executes the command. [args] is the trailing text after the command word.
  final Future<void> Function(BuildContext context, String args) run;

  bool matches(String token) {
    final t = token.toLowerCase();
    return name.startsWith(t) || aliases.any((a) => a.startsWith(t));
  }
}

/// The full command registry. Session ops go through [ChatViewModel]; admin
/// commands push the model/MCP pages; read commands open info sheets.
final List<SlashCommand> kSlashCommands = [
  SlashCommand(
    name: 'new',
    aliases: ['clear'],
    description: 'Start a fresh conversation',
    icon: Icons.add_comment_outlined,
    run: (ctx, _) async => ctx.read<ChatViewModel>().newChat(),
  ),
  SlashCommand(
    name: 'branch',
    aliases: ['fork'],
    description: 'Branch this conversation',
    icon: Icons.call_split,
    run: (ctx, _) async => ctx.read<ChatViewModel>().fork(),
  ),
  SlashCommand(
    name: 'rename',
    aliases: ['title'],
    description: 'Rename this conversation',
    icon: Icons.edit_outlined,
    argHint: '<new title>',
    run: (ctx, args) async {
      if (args.trim().isNotEmpty) await ctx.read<ChatViewModel>().rename(args.trim());
    },
  ),
  SlashCommand(
    name: 'sessions',
    aliases: ['history'],
    description: 'Browse conversation history',
    icon: Icons.history,
    run: (ctx, _) async => showSessionDrawer(ctx),
  ),
  SlashCommand(
    name: 'delete',
    description: 'Delete this conversation',
    icon: Icons.delete_outline,
    run: (ctx, _) async => ctx.read<ChatViewModel>().deleteCurrent(),
  ),
  SlashCommand(
    name: 'stop',
    description: 'Stop the current response',
    icon: Icons.stop_circle_outlined,
    run: (ctx, _) async => ctx.read<ChatViewModel>().stop(),
  ),
  SlashCommand(
    name: 'model',
    description: 'Switch the AI model',
    icon: Icons.memory,
    run: (ctx, _) async => openModelSwitcher(ctx),
  ),
  SlashCommand(
    name: 'mcp',
    description: 'Manage MCP servers',
    icon: Icons.extension_outlined,
    run: (ctx, _) async => openMcpScreen(ctx),
  ),
  SlashCommand(
    name: 'remind',
    aliases: ['reminders', 'alarm'],
    description: 'Alarms & scheduled tasks',
    icon: Icons.alarm,
    run: (ctx, _) async => openReminders(ctx),
  ),
  SlashCommand(
    name: 'tools',
    aliases: ['toolsets'],
    description: 'List available toolsets',
    icon: Icons.build_outlined,
    run: (ctx, _) async => _showListSheet(
      ctx,
      title: 'Toolsets',
      load: () async {
        final rows = await ctx.read<SystemRepository>().toolsets();
        return rows
            .map((t) => _SheetRow(
                  title: (t['label'] ?? t['name'] ?? '').toString(),
                  subtitle: (t['description'] ?? '').toString(),
                  on: t['enabled'] == true,
                ))
            .toList();
      },
    ),
  ),
  SlashCommand(
    name: 'skills',
    description: 'List installed skills',
    icon: Icons.auto_awesome_outlined,
    run: (ctx, _) async => _showListSheet(
      ctx,
      title: 'Skills',
      load: () async {
        final rows = await ctx.read<SystemRepository>().skills();
        return rows
            .map((s) => _SheetRow(
                  title: (s['name'] ?? '').toString(),
                  subtitle: (s['description'] ?? '').toString(),
                ))
            .toList();
      },
    ),
  ),
  SlashCommand(
    name: 'help',
    description: 'Show all commands',
    icon: Icons.help_outline,
    run: (ctx, _) async => _showListSheet(
      ctx,
      title: 'Commands',
      load: () async => kSlashCommands
          .map((c) => _SheetRow(title: '/${c.name}', subtitle: c.description))
          .toList(),
    ),
  ),
];

/// Parse a raw input line. Returns the matching command + trailing args, or
/// null if it isn't a recognized slash command.
({SlashCommand command, String args})? resolveSlash(String raw) {
  final text = raw.trimLeft();
  if (!text.startsWith('/')) return null;
  final body = text.substring(1);
  final spaceIdx = body.indexOf(' ');
  final word = (spaceIdx == -1 ? body : body.substring(0, spaceIdx)).toLowerCase();
  final args = spaceIdx == -1 ? '' : body.substring(spaceIdx + 1);
  for (final c in kSlashCommands) {
    if (c.name == word || c.aliases.contains(word)) {
      return (command: c, args: args);
    }
  }
  return null;
}

/// Commands whose `name`/alias starts with the partial token being typed.
List<SlashCommand> filterSlash(String raw) {
  final text = raw.trimLeft();
  if (!text.startsWith('/')) return const [];
  final body = text.substring(1);
  if (body.contains(' ')) return const []; // past the command word
  if (body.isEmpty) return kSlashCommands;
  return kSlashCommands.where((c) => c.matches(body)).toList();
}

// --- read-only info sheet ---------------------------------------------------

class _SheetRow {
  _SheetRow({required this.title, this.subtitle = '', this.on});
  final String title;
  final String subtitle;
  final bool? on;
}

Future<void> _showListSheet(
  BuildContext context, {
  required String title,
  required Future<List<_SheetRow>> Function() load,
}) async {
  final atl = context.atl;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: atl.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(title, style: atlSerif(size: 22, color: atl.text)),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<_SheetRow>>(
                future: load(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('${snap.error}', style: atlSans(size: 13, color: atl.text2)),
                    );
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Nothing to show.', style: atlSans(size: 14, color: atl.text2)),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.title,
                                      style: atlSans(
                                          size: 15, color: atl.text, weight: FontWeight.w600)),
                                  if (r.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(r.subtitle,
                                        style: atlSans(size: 12, color: atl.text3)),
                                  ],
                                ],
                              ),
                            ),
                            if (r.on != null)
                              Icon(
                                r.on! ? Icons.check_circle : Icons.circle_outlined,
                                size: 18,
                                color: r.on! ? atl.accent : atl.text3,
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
