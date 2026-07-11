import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../domain/models/message.dart';
import '../../../core/animations.dart';
import '../../../core/atl_theme.dart';
import '../../shell/shell_controller.dart';
import '../../today/today_screen.dart' show kAssistantName;
import '../slash/slash_commands.dart';
import '../slash/slash_palette.dart';
import '../view_models/chat_view_model.dart';
import 'session_drawer.dart';

/// Conversation surface, styled to the Atlantic design. Streams replies via the
/// existing [ChatViewModel] (SSE); the mic opens the Halo voice overlay.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Rebuild as the user types so the slash palette filters live.
    _controller.addListener(_onInputChanged);
  }

  void _onInputChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Selecting a palette entry: commands that take an argument pre-fill the
  /// input; the rest run immediately and clear the field.
  Future<void> _selectCommand(SlashCommand c) async {
    if (c.argHint != null) {
      final text = '/${c.name} ';
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      return;
    }
    _controller.clear();
    await c.run(context, '');
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<ChatViewModel>();
    final shell = context.read<ShellController>();
    _autoScroll();

    final error = vm.error;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(error)));
        vm.clearError();
      });
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: atl.divider)),
          ),
          child: Row(
            children: [
              Pressable(
                onTap: () => showSessionDrawer(context),
                child: Icon(Icons.history, size: 22, color: atl.text2),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      vm.current == null ? kAssistantName : vm.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: atlSans(size: 16, color: atl.text, weight: FontWeight.w600),
                    ),
                    Text(
                      vm.current == null ? 'New chat' : '● Connected',
                      style: atlSans(
                          size: 11,
                          color: vm.current == null
                              ? atl.text3
                              : const Color(0xFF1EA88A)),
                    ),
                  ],
                ),
              ),
              Pressable(
                onTap: vm.newChat,
                child: Icon(Icons.add, size: 23, color: atl.accent),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: vm.loadingHistory
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : vm.messages.isEmpty
                  ? _empty(atl)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                      itemCount: vm.messages.length,
                      itemBuilder: (_, i) => FadeInUp(
                        key: ValueKey(i),
                        duration: const Duration(milliseconds: 300),
                        child: _bubble(atl, vm.messages[i]),
                      ),
                    ),
        ),

        if (vm.isTranscribing) _statusChip(atl, 'Transcribing…'),
        if (vm.toolStatus.isNotEmpty) _statusChip(atl, vm.toolStatus),

        // Slash-command palette (only while typing a `/` command)
        SlashPalette(
          commands: filterSlash(_controller.text),
          onSelect: _selectCommand,
        ),

        // Input bar
        _inputBar(atl, vm, shell),
      ],
    );
  }

  Widget _empty(AtlColors atl) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 44, color: atl.accent),
              const SizedBox(height: 14),
              Text('Ask $kAssistantName anything',
                  style: atlSerif(size: 24, color: atl.text)),
              const SizedBox(height: 6),
              Text('Type a message or tap the mic to talk.',
                  textAlign: TextAlign.center,
                  style: atlSans(size: 14, color: atl.text2)),
            ],
          ),
        ),
      );

  Widget _bubble(AtlColors atl, Message m) {
    final isUser = m.role == MessageRole.user;
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            gradient: atl.userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(m.content,
              style: atlSans(size: 15, color: atl.userInk, weight: FontWeight.w500, height: 1.45)),
        ),
      );
    }
    // Assistant — with a streaming caret while filling.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 40),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: atl.surface,
          border: Border.all(color: atl.hairline),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: atl.cardShadow,
        ),
        child: m.content.isEmpty && m.streaming
            ? SizedBox(
                width: 30,
                child: Text('…', style: atlSans(size: 18, color: atl.text2)),
              )
            : Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: m.content,
                    style: atlSans(size: 15, color: atl.text, height: 1.5),
                  ),
                  if (m.streaming)
                    TextSpan(
                      text: ' |',
                      style: atlSans(size: 15, color: atl.accent, weight: FontWeight.w700),
                    ),
                ]),
              ),
      ),
    );
  }

  Widget _statusChip(AtlColors atl, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(text, style: atlSans(size: 13, color: atl.text2)),
          ],
        ),
      );

  Widget _inputBar(AtlColors atl, ChatViewModel vm, ShellController shell) {
    void submit() {
      final text = _controller.text;
      if (text.trim().isEmpty) return;
      // Intercept `/` commands so they run instead of being sent as a message.
      final slash = resolveSlash(text);
      if (slash != null) {
        _controller.clear();
        slash.command.run(context, slash.args);
        return;
      }
      _controller.clear();
      vm.sendText(text);
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: atl.frost,
            border: Border(top: BorderSide(color: atl.divider)),
          ),
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              decoration: BoxDecoration(
                color: atl.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: atl.fieldBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => submit(),
                      style: atlSans(size: 15, color: atl.text),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Message $kAssistantName…',
                        hintStyle: atlSans(size: 15, color: atl.text3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: shell.openVoice,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: atl.surface2),
                      child: Icon(Icons.mic_none, size: 18, color: atl.text2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Pressable(
                    onTap: (vm.isSending || vm.isTranscribing) ? null : submit,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
                        ),
                      ),
                      child: const Icon(Icons.arrow_upward, size: 21, color: Color(0xFF0A0A14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
