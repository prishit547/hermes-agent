import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/code_repository.dart';
import '../../../domain/models/code_project.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import 'code_session_screen.dart';
import 'code_usage_sheet.dart';
import 'code_view_model.dart';

/// Open Atlantic Dev — the Claude Code surface. Creates one [CodeViewModel] for
/// the whole flow (project picker → live session → diff/commit) and provides it
/// down the pushed route, mirroring [openMcpScreen].
Future<void> openCodeScreen(BuildContext context) {
  final repo = context.read<CodeRepository>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => CodeViewModel(repo)
          ..loadProjects()
          ..loadUsage(),
        child: const CodeScreen(),
      ),
    ),
  );
}

/// Lists the whitelisted repos. Tapping one picks a permission mode and starts a
/// Claude Code session on it.
class CodeScreen extends StatelessWidget {
  const CodeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<CodeViewModel>();
    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: atl.text,
          title: Text('Atlantic Dev',
              style: atlSans(size: 18, color: atl.text, weight: FontWeight.w600)),
          actions: [
            IconButton(
              tooltip: 'Usage',
              icon: Icon(Icons.query_stats_rounded, color: atl.text2),
              onPressed: () => showUsageSheet(context, vm),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: () => Future.wait([vm.loadProjects(), vm.loadUsage()]),
            color: atl.accent,
            child: _body(context, atl, vm),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AtlColors atl, CodeViewModel vm) {
    if (vm.loadingProjects && vm.projects.isEmpty) {
      return Center(child: CircularProgressIndicator(color: atl.accent));
    }
    if (vm.projectsError != null && vm.projects.isEmpty) {
      return _emptyState(
        atl,
        icon: Icons.error_outline,
        title: 'Could not load projects',
        body: vm.projectsError!,
      );
    }
    if (vm.projects.isEmpty) {
      return _emptyState(
        atl,
        icon: Icons.folder_off_outlined,
        title: 'No projects configured',
        body: 'Add repositories under `claude_code.projects` in '
            '~/.hermes/config.yaml on the gateway, then pull to refresh.',
      );
    }
    final showUsage = vm.usage != null;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: vm.projects.length + (showUsage ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (showUsage && i == 0) return _usageCard(context, atl, vm);
        final p = vm.projects[showUsage ? i - 1 : i];
        return _projectCard(context, atl, vm, p);
      },
    );
  }

  Widget _usageCard(BuildContext context, AtlColors atl, CodeViewModel vm) {
    final usage = vm.usage!;
    final anyLimited = (usage.sessionUsedPct ?? 0) >= 100 || (usage.weekUsedPct ?? 0) >= 100;
    final lastReset = usage.resetEvents.isNotEmpty ? usage.resetEvents.first : null;

    return GestureDetector(
      onTap: () => showUsageSheet(context, vm),
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: anyLimited ? atl.accentSoft : atl.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: anyLimited ? atl.accent.withValues(alpha: 0.5) : atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.query_stats_rounded, size: 16, color: atl.text2),
              const SizedBox(width: 8),
              Text('Usage',
                  style: atlSans(size: 13, color: atl.text2, weight: FontWeight.w700)),
              const Spacer(),
              Text(_fmtUsd(usage.totalCostUsd),
                  style: atlSans(size: 13, color: atl.text, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('· ${usage.totalTurns} turns',
                  style: atlSans(size: 12, color: atl.text3)),
              const SizedBox(width: 4),
              _refreshButton(atl, vm),
            ],
          ),
          if (usage.hasUsageCheck) ...[
            const SizedBox(height: 14),
            if (usage.sessionUsedPct != null)
              _usageRow(atl, label: 'Session', pct: usage.sessionUsedPct!, resetsAt: usage.sessionResetsAtTime),
            if (usage.weekUsedPct != null) ...[
              const SizedBox(height: 10),
              _usageRow(atl, label: 'This week', pct: usage.weekUsedPct!, resetsAt: usage.weekResetsAtTime),
            ],
          ] else if (!vm.loadingUsage) ...[
            const SizedBox(height: 8),
            Text('Tap the refresh icon to check your usage.',
                style: atlSans(size: 12, color: atl.text3)),
          ],
          if (lastReset != null) ...[
            const SizedBox(height: 10),
            Text(
              '${lastReset.window == 'week' ? 'Weekly' : 'Session'} limit reset ${_fmtAgo(lastReset.atTime)}',
              style: atlSans(size: 11, color: atl.text3),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _usageRow(AtlColors atl, {required String label, required int pct, DateTime? resetsAt}) {
    final limited = pct >= 100;
    final barColor = limited ? Colors.redAccent.shade200 : (pct >= 80 ? atl.accent : atl.accentInk);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600)),
            const Spacer(),
            Text('$pct% used',
                style: atlSans(
                    size: 12,
                    color: limited ? Colors.redAccent.shade200 : atl.text2,
                    weight: limited ? FontWeight.w700 : FontWeight.w400)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: atl.surface2,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
        if (resetsAt != null) ...[
          const SizedBox(height: 4),
          Text('Resets in ${_fmtCountdown(resetsAt)}',
              style: atlSans(size: 11, color: atl.text3)),
        ],
      ],
    );
  }

  Widget _refreshButton(AtlColors atl, CodeViewModel vm) {
    return GestureDetector(
      onTap: vm.checkingUsage ? null : vm.checkUsageNow,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: vm.checkingUsage
            ? SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: atl.text3))
            : Icon(Icons.refresh_rounded, size: 16, color: atl.text3),
      ),
    );
  }

  String _fmtUsd(double v) => '\$${v.toStringAsFixed(2)}';

  String _fmtCountdown(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return 'a moment';
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return '<1m';
  }

  String _fmtAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  Widget _projectCard(BuildContext context, AtlColors atl, CodeViewModel vm, CodeProject p) {
    return Pressable(
      onTap: () => _pickModeAndStart(context, vm, p),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: atl.hairline),
          boxShadow: atl.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: atl.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.terminal_rounded, color: atl.accentInk, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: atlSans(size: 16, color: atl.text, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    p.isRepo
                        ? '${p.branch ?? "?"}${p.isDirty ? " · ${p.dirty} changed" : " · clean"}'
                        : p.path,
                    style: atlMono(size: 11, color: atl.text3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (p.isDirty)
              Container(
                margin: const EdgeInsets.only(left: 8),
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: atl.accent, shape: BoxShape.circle),
              ),
            Icon(Icons.chevron_right, color: atl.text3),
          ],
        ),
      ),
    );
  }

  Future<void> _pickModeAndStart(BuildContext context, CodeViewModel vm, CodeProject p) async {
    final atl = context.atl;
    final mode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: atl.elevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Start on ${p.name}',
                  style: atlSans(size: 17, color: atl.text, weight: FontWeight.w700)),
              const SizedBox(height: 16),
              _modeOption(context, atl,
                  mode: 'plan',
                  icon: Icons.checklist_rounded,
                  title: 'Plan & build',
                  subtitle: 'Claude investigates and proposes a plan first. '
                      'Approve it to auto-build — recommended.'),
              const SizedBox(height: 10),
              _modeOption(context, atl,
                  mode: 'default',
                  icon: Icons.chat_bubble_outline,
                  title: 'Chat',
                  subtitle: 'Ask questions. Read-only, no file changes.'),
              const SizedBox(height: 10),
              _modeOption(context, atl,
                  mode: 'approve',
                  icon: Icons.verified_user_outlined,
                  title: 'Make changes',
                  subtitle: 'Claude edits and runs commands, but you approve '
                      'each action from your phone.'),
            ],
          ),
        ),
      ),
    );
    if (mode == null || !context.mounted) return;
    try {
      await vm.startSession(p, mode: mode);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: vm,
            child: const CodeSessionScreen(),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start session: $e')),
      );
    }
  }

  Widget _modeOption(BuildContext context, AtlColors atl,
      {required String mode,
      required IconData icon,
      required String title,
      required String subtitle}) {
    return Pressable(
      onTap: () => Navigator.of(context).pop(mode),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: atl.hairline),
        ),
        child: Row(
          children: [
            Icon(icon, color: atl.accentInk, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: atlSans(size: 12, color: atl.text3, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(AtlColors atl,
      {required IconData icon, required String title, required String body}) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 48, color: atl.text3),
        const SizedBox(height: 16),
        Center(
          child: Text(title, style: atlSans(size: 17, color: atl.text, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(body,
              textAlign: TextAlign.center, style: atlSans(size: 13, color: atl.text3, height: 1.4)),
        ),
      ],
    );
  }
}
