import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import 'code_usage_sheet.dart';
import 'code_view_model.dart';

/// The live Claude Code session: streamed transcript, a composer with a
/// Chat/Edit mode toggle, and the diff → commit review loop.
class CodeSessionScreen extends StatefulWidget {
  const CodeSessionScreen({super.key});

  @override
  State<CodeSessionScreen> createState() => _CodeSessionScreenState();
}

class _CodeSessionScreenState extends State<CodeSessionScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _modeSubtitle(String mode) => switch (mode) {
        'plan' => 'Plan mode · proposes a plan to approve',
        'approve' => 'Approve mode · you OK each action',
        'acceptEdits' => 'Auto mode · edits apply automatically',
        _ => 'Chat · read-only',
      };

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
    final vm = context.watch<CodeViewModel>();
    _autoScroll();
    final session = vm.session;
    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: atl.text,
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session?.project ?? 'Session',
                  style: atlSans(size: 16, color: atl.text, weight: FontWeight.w600)),
              Text(_modeSubtitle(vm.permissionMode),
                  style: atlSans(size: 11, color: atl.text3)),
            ],
          ),
          actions: [
            if (vm.liveRateLimit?.isLimited ?? false)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: atl.accentSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Limit reached',
                        style: atlSans(size: 11, color: atl.accentInk, weight: FontWeight.w600)),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Usage',
              icon: Icon(Icons.query_stats_rounded, color: atl.text2),
              onPressed: () => showUsageSheet(context, vm),
            ),
            IconButton(
              tooltip: 'Review changes',
              icon: Icon(Icons.difference_outlined, color: atl.text2),
              onPressed: () => _openDiff(context, vm),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(child: _transcript(atl, vm)),
              _composer(context, atl, vm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transcript(AtlColors atl, CodeViewModel vm) {
    if (vm.transcript.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Ask Claude Code to explore, explain, or change ${vm.session?.project ?? "this project"}.',
            textAlign: TextAlign.center,
            style: atlSans(size: 14, color: atl.text3, height: 1.4),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: vm.transcript.length,
      itemBuilder: (_, i) => _item(atl, vm.transcript[i]),
    );
  }

  Widget _item(AtlColors atl, CodeItem item) {
    return switch (item) {
      UserItem(:final text) => _bubble(atl, text, isUser: true),
      AssistantItem(:final text) => _bubble(atl, text, isUser: false),
      ToolItem() => _toolRow(atl, item),
      SummaryItem(:final text) => _summary(atl, text),
      ResultItem() => _result(atl, item),
      ErrorItem(:final message) => _error(atl, message),
      PermissionItem() => _permission(atl, item),
      PlanItem() => _plan(atl, item),
    };
  }

  Widget _plan(AtlColors atl, PlanItem p) {
    final vm = context.read<CodeViewModel>();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: atl.accent.withValues(alpha: 0.6)),
        boxShadow: atl.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 16, color: atl.accentInk),
              const SizedBox(width: 8),
              Text('Plan ready',
                  style: atlSans(size: 13, color: atl.accentInk, weight: FontWeight.w700)),
              const Spacer(),
              if (p.approved)
                Text('Building…', style: atlSans(size: 11, color: atl.text3)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: atl.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: atl.hairline),
            ),
            child: SelectableText(p.plan.isEmpty ? '(no plan text)' : p.plan,
                style: atlSans(size: 13, color: atl.text, height: 1.4)),
          ),
          if (!p.approved) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _planButton(atl,
                      label: 'Approve & build',
                      filled: true,
                      onTap: () => vm.approvePlanAndBuild(p, mode: 'acceptEdits')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _planButton(atl,
                      label: 'Approve each step',
                      filled: false,
                      onTap: () => vm.approvePlanAndBuild(p, mode: 'approve')),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Auto applies edits automatically; "each step" asks you before every action.',
                style: atlSans(size: 10, color: atl.text3, height: 1.3)),
          ],
        ],
      ),
    );
  }

  Widget _planButton(AtlColors atl,
      {required String label, required bool filled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: filled ? atl.accent : atl.surface,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: atl.hairline),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: atlSans(
                size: 13,
                color: filled ? atl.accentInk : atl.text2,
                weight: FontWeight.w600)),
      ),
    );
  }

  Widget _permission(AtlColors atl, PermissionItem p) {
    final vm = context.read<CodeViewModel>();
    final pending = p.resolved == null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: atl.accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: atl.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 16, color: atl.accentInk),
              const SizedBox(width: 8),
              Text(
                pending
                    ? 'Approve ${p.tool}?'
                    : (p.resolved! ? '${p.tool} approved' : '${p.tool} denied'),
                style: atlSans(size: 13, color: atl.accentInk, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: atl.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: atl.hairline),
            ),
            child: Text(p.summary.isEmpty ? '(no detail)' : p.summary,
                style: atlMono(size: 11, color: atl.text2), maxLines: 6, overflow: TextOverflow.ellipsis),
          ),
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _permButton(atl, label: 'Deny', filled: false,
                      busy: p.sending, onTap: () => vm.respondPermission(p, false)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _permButton(atl, label: 'Allow', filled: true,
                      busy: p.sending, onTap: () => vm.respondPermission(p, true)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _permButton(AtlColors atl,
      {required String label, required bool filled, required bool busy, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? atl.accent : atl.surface,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: atl.hairline),
        ),
        child: busy
            ? SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: filled ? atl.accentInk : atl.text2))
            : Text(label,
                style: atlSans(
                    size: 14,
                    color: filled ? atl.accentInk : atl.text2,
                    weight: FontWeight.w600)),
      ),
    );
  }

  Widget _bubble(AtlColors atl, String text, {required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? atl.accent : atl.surface,
          borderRadius: BorderRadius.circular(16),
          border: isUser ? null : Border.all(color: atl.hairline),
        ),
        child: SelectableText(
          text.isEmpty ? '…' : text,
          style: atlSans(size: 14, color: isUser ? atl.accentInk : atl.text, height: 1.35),
        ),
      ),
    );
  }

  Widget _toolRow(AtlColors atl, ToolItem t) {
    final Color dot = !t.done
        ? atl.accent
        : (t.isError ? Colors.redAccent : atl.text3);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: atl.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: atl.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: t.done
                ? Icon(t.isError ? Icons.close : Icons.check, size: 14, color: dot)
                : SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: dot),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.tool,
                    style: atlSans(size: 13, color: atl.text2, weight: FontWeight.w600)),
                if (t.input != null && t.input!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(t.input!,
                        style: atlMono(size: 11, color: atl.text3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(AtlColors atl, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.subject, size: 13, color: atl.text3),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: atlSans(size: 11, color: atl.text3, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Widget _result(AtlColors atl, ResultItem r) {
    if (r.denials.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: atl.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.denials.length} action(s) blocked in read-only mode',
              style: atlSans(size: 12, color: atl.accentInk, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Switch to Edit mode below and re-ask to let Claude make changes.',
              style: atlSans(size: 12, color: atl.accentInk, height: 1.3)),
        ],
      ),
    );
  }

  Widget _error(AtlColors atl, String message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: atlSans(size: 13, color: Colors.red.shade300)),
    );
  }

  Widget _composer(BuildContext context, AtlColors atl, CodeViewModel vm) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: atl.frost,
        border: Border(top: BorderSide(color: atl.hairline)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _modeChip(atl, vm, label: 'Plan', mode: 'plan'),
                      const SizedBox(width: 6),
                      _modeChip(atl, vm, label: 'Chat', mode: 'default'),
                      const SizedBox(width: 6),
                      _modeChip(atl, vm, label: 'Approve', mode: 'approve'),
                      const SizedBox(width: 6),
                      _modeChip(atl, vm, label: 'Auto', mode: 'acceptEdits'),
                    ],
                  ),
                ),
              ),
              if (vm.streaming) ...[
                const SizedBox(width: 8),
                Text('Working…', style: atlSans(size: 12, color: atl.text3)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !vm.streaming,
                  minLines: 1,
                  maxLines: 5,
                  style: atlSans(size: 14, color: atl.text),
                  decoration: InputDecoration(
                    hintText: 'Message Claude Code…',
                    hintStyle: atlSans(size: 14, color: atl.text3),
                    filled: true,
                    fillColor: atl.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: atl.fieldBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: atl.fieldBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: atl.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _sendButton(atl, vm),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeChip(AtlColors atl, CodeViewModel vm, {required String label, required String mode}) {
    final selected = vm.permissionMode == mode;
    return Pressable(
      onTap: vm.streaming ? null : () => vm.setPermissionMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? atl.accent : atl.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? atl.accent : atl.hairline),
        ),
        child: Text(label,
            style: atlSans(
                size: 12,
                color: selected ? atl.accentInk : atl.text2,
                weight: FontWeight.w600)),
      ),
    );
  }

  Widget _sendButton(AtlColors atl, CodeViewModel vm) {
    final busy = vm.streaming;
    return GestureDetector(
      onTap: () {
        if (busy) {
          vm.interrupt();
        } else {
          final text = _controller.text;
          _controller.clear();
          vm.send(text);
        }
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: busy ? atl.surface2 : atl.accent,
          borderRadius: BorderRadius.circular(14),
          border: busy ? Border.all(color: atl.hairline) : null,
        ),
        child: Icon(busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            color: busy ? atl.text2 : atl.accentInk),
      ),
    );
  }

  // -- diff / commit -----------------------------------------------------
  void _openDiff(BuildContext context, CodeViewModel vm) {
    vm.loadDiff();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.atl.elevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: const _DiffSheet(),
      ),
    );
  }
}

class _DiffSheet extends StatelessWidget {
  const _DiffSheet();

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<CodeViewModel>();
    final diff = vm.diff;
    final diffText = (diff?['diff'] as String?) ?? '';
    final stat = (diff?['stat'] as String?) ?? '';
    final untracked = (diff?['untracked'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final hasChanges = diffText.trim().isNotEmpty || untracked.isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text('Changes',
                    style: atlSans(size: 17, color: atl.text, weight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () => _prFlow(context, vm),
                  child: Text('Open PR…',
                      style: atlSans(size: 14, color: atl.text2, weight: FontWeight.w600)),
                ),
                if (hasChanges)
                  TextButton(
                    onPressed: () => _commitFlow(context, vm),
                    child: Text('Commit…',
                        style: atlSans(size: 14, color: atl.accentInk, weight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          if (stat.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(stat.trim(), style: atlMono(size: 11, color: atl.text3)),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: vm.loadingDiff
                ? Center(child: CircularProgressIndicator(color: atl.accent))
                : !hasChanges
                    ? Center(
                        child: Text('No uncommitted changes.',
                            style: atlSans(size: 14, color: atl.text3)))
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          if (untracked.isNotEmpty) ...[
                            Text('New files',
                                style: atlSans(size: 12, color: atl.text3, weight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            ...untracked.map((u) => Text('+ $u',
                                style: atlMono(size: 11, color: atl.text2))),
                            const SizedBox(height: 12),
                          ],
                          if (diffText.trim().isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: atl.surface2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: atl.hairline),
                              ),
                              child: _DiffText(diffText, atl: atl),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _commitFlow(BuildContext context, CodeViewModel vm) async {
    final atl = context.atl;
    final msgController = TextEditingController();
    bool push = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setState) => AlertDialog(
          backgroundColor: atl.elevated,
          title: Text('Commit changes',
              style: atlSans(size: 16, color: atl.text, weight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: msgController,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                style: atlSans(size: 14, color: atl.text),
                decoration: InputDecoration(
                  hintText: 'Commit message',
                  hintStyle: atlSans(size: 14, color: atl.text3),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: push,
                    activeColor: atl.accent,
                    onChanged: (v) => setState(() => push = v ?? false),
                  ),
                  Text('Push after commit',
                      style: atlSans(size: 13, color: atl.text2)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text('Cancel', style: atlSans(size: 14, color: atl.text3)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text('Commit',
                  style: atlSans(size: 14, color: atl.accentInk, weight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (go != true || msgController.text.trim().isEmpty || !context.mounted) return;
    try {
      final result = await vm.commit(msgController.text.trim(), push: push);
      if (!context.mounted) return;
      final ok = result['ok'] == true;
      final pushInfo = result['push'] as Map<String, dynamic>?;
      final msg = ok
          ? (pushInfo != null
              ? (pushInfo['ok'] == true ? 'Committed and pushed.' : 'Committed. Push failed.')
              : 'Committed.')
          : 'Commit failed: ${result['error'] ?? 'unknown'}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Commit error: $e')));
    }
  }

  Future<void> _prFlow(BuildContext context, CodeViewModel vm) async {
    final atl = context.atl;
    final titleController = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: atl.elevated,
        title: Text('Open pull request',
            style: atlSans(size: 16, color: atl.text, weight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pushes the current branch and runs `gh pr create`.',
                style: atlSans(size: 12, color: atl.text3, height: 1.3)),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              autofocus: true,
              style: atlSans(size: 14, color: atl.text),
              decoration: InputDecoration(
                hintText: 'PR title (optional — autofilled from commits)',
                hintStyle: atlSans(size: 13, color: atl.text3),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel', style: atlSans(size: 14, color: atl.text3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text('Open PR',
                style: atlSans(size: 14, color: atl.accentInk, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening PR…')));
    try {
      final r = await vm.openPr(
          title: titleController.text.trim().isEmpty ? null : titleController.text.trim());
      if (!context.mounted) return;
      final ok = r['ok'] == true;
      final msg = ok
          ? 'PR opened: ${r['url'] ?? 'created'}'
          : 'PR failed (${r['stage'] ?? 'gh'}): ${r['error'] ?? 'unknown'}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PR error: $e')));
    }
  }
}

/// Renders a unified diff with per-line +/- tinting.
class _DiffText extends StatelessWidget {
  const _DiffText(this.diff, {required this.atl});
  final String diff;
  final AtlColors atl;

  @override
  Widget build(BuildContext context) {
    final lines = diff.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((l) {
        Color color = atl.text2;
        if (l.startsWith('+') && !l.startsWith('+++')) {
          color = Colors.greenAccent.shade400;
        } else if (l.startsWith('-') && !l.startsWith('---')) {
          color = Colors.redAccent.shade200;
        } else if (l.startsWith('@@')) {
          color = atl.accentInk;
        } else if (l.startsWith('diff ') || l.startsWith('index ')) {
          color = atl.text3;
        }
        return Text(l.isEmpty ? ' ' : l, style: atlMono(size: 11, color: color));
      }).toList(),
    );
  }
}
