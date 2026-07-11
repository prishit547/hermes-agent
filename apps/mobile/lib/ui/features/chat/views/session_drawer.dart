import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/animations.dart';
import '../../../core/atl_theme.dart';
import '../../../../domain/models/session_summary.dart';
import '../view_models/chat_view_model.dart';
import '../view_models/session_list_view_model.dart';

/// Opens the conversation-history sheet. Lets the user switch to a past
/// conversation, filter by scope (this app vs all devices), start a new chat,
/// or delete a conversation.
Future<void> showSessionDrawer(BuildContext context) async {
  final chat = context.read<ChatViewModel>();
  final list = context.read<SessionListViewModel>();
  // Refresh on open so the list reflects the latest server state.
  list.refresh();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider.value(value: list),
      ],
      child: const _SessionSheet(),
    ),
  );
}

class _SessionSheet extends StatelessWidget {
  const _SessionSheet();

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final list = context.watch<SessionListViewModel>();
    final chat = context.read<ChatViewModel>();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: atl.frost,
            border: Border(top: BorderSide(color: atl.divider)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: atl.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header row
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 6),
                  child: Row(
                    children: [
                      Text('Conversations',
                          style: atlSerif(size: 24, color: atl.text)),
                      const Spacer(),
                      Pressable(
                        onTap: () {
                          chat.newChat();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add, size: 17, color: Color(0xFF0A0A14)),
                              const SizedBox(width: 5),
                              Text('New',
                                  style: atlSans(
                                      size: 13,
                                      color: const Color(0xFF0A0A14),
                                      weight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Scope filter
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: atl.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: atl.hairline),
                    ),
                    child: Row(
                      children: [
                        _scopeSeg(atl, 'This app', list.thisAppOnly,
                            () => list.setThisAppOnly(true)),
                        _scopeSeg(atl, 'All devices', !list.thisAppOnly,
                            () => list.setThisAppOnly(false)),
                      ],
                    ),
                  ),
                ),
                Flexible(child: _body(context, atl, list, chat)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AtlColors atl, SessionListViewModel list,
      ChatViewModel chat) {
    if (list.loading && list.sessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (list.error != null && list.sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(30),
        child: Text(list.error!,
            textAlign: TextAlign.center,
            style: atlSans(size: 14, color: atl.text2)),
      );
    }
    if (list.sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 40, color: atl.text3),
            const SizedBox(height: 12),
            Text('No conversations yet',
                style: atlSans(size: 15, color: atl.text2)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      itemCount: list.sessions.length,
      itemBuilder: (_, i) {
        final s = list.sessions[i];
        final active = chat.currentSessionId == s.id;
        return _sessionTile(context, atl, s, active, list, chat);
      },
    );
  }

  Widget _sessionTile(BuildContext context, AtlColors atl, SessionSummary s,
      bool active, SessionListViewModel list, ChatViewModel chat) {
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AtlColors.danger.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: AtlColors.danger),
      ),
      onDismissed: (_) {
        list.delete(s.id);
        if (chat.currentSessionId == s.id) chat.newChat();
      },
      child: Pressable(
        onTap: () {
          chat.switchTo(s);
          Navigator.of(context).pop();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: active ? atl.accentSoft : atl.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? atl.accent : atl.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: atlSans(
                          size: 15,
                          color: atl.text,
                          weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (!s.isThisApp) ...[
                          _sourceBadge(atl, s.source),
                          const SizedBox(width: 7),
                        ],
                        Text('${s.messageCount} msgs',
                            style: atlSans(size: 12, color: atl.text3)),
                      ],
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(Icons.check_circle, size: 18, color: atl.accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceBadge(AtlColors atl, String source) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: atl.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: atl.hairline),
        ),
        child: Text(source.isEmpty ? 'other' : source,
            style: atlSans(size: 10, color: atl.text2, weight: FontWeight.w500)),
      );

  Widget _scopeSeg(AtlColors atl, String label, bool active, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: active ? atl.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: atlSans(
                    size: 12,
                    color: active ? atl.accentInk : atl.text2,
                    weight: active ? FontWeight.w600 : FontWeight.w500)),
          ),
        ),
      );
}
