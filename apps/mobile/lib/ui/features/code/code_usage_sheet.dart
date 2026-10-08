import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/atl_theme.dart';
import 'code_view_model.dart';

/// Open the detailed usage sheet. Reused from the project picker and from an
/// active session, so usage is viewable directly anywhere in the Code section.
void showUsageSheet(BuildContext context, CodeViewModel vm) {
  vm.loadUsage();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.atl.elevated,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => ChangeNotifierProvider.value(value: vm, child: const _UsageSheet()),
  );
}

class _UsageSheet extends StatelessWidget {
  const _UsageSheet();

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<CodeViewModel>();
    final usage = vm.usage;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            children: [
              Icon(Icons.query_stats_rounded, size: 18, color: atl.text2),
              const SizedBox(width: 8),
              Text('Claude Code usage',
                  style: atlSans(size: 17, color: atl.text, weight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: vm.checkingUsage ? null : vm.checkUsageNow,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: vm.checkingUsage
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: atl.text3))
                      : Icon(Icons.refresh_rounded, size: 18, color: atl.accentInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            usage?.checkedAt != null
                ? 'Checked ${_fmtAgo(_toTime(usage!.checkedAt!))} · free /usage check'
                : 'Tap refresh to check your limits (free).',
            style: atlSans(size: 11, color: atl.text3),
          ),
          const SizedBox(height: 18),

          if (usage == null)
            Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(color: atl.accent),
            ))
          else ...[
            if (usage.hasUsageCheck) ...[
              if (usage.sessionUsedPct != null)
                _bar(atl, 'Session (5-hour)', usage.sessionUsedPct!, usage.sessionResetsAtTime),
              if (usage.weekUsedPct != null) ...[
                const SizedBox(height: 14),
                _bar(atl, 'This week', usage.weekUsedPct!, usage.weekResetsAtTime),
              ],
              const SizedBox(height: 20),
            ],

            Row(
              children: [
                Expanded(child: _stat(atl, 'Total cost', _fmtUsd(usage.totalCostUsd))),
                Expanded(child: _stat(atl, 'Turns', '${usage.totalTurns}')),
              ],
            ),

            if (usage.perProjectCostUsd.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('By project',
                  style: atlSans(size: 12, color: atl.text3, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...usage.perProjectCostUsd.entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text(e.key,
                          style: atlSans(size: 13, color: atl.text2),
                          overflow: TextOverflow.ellipsis)),
                      Text(_fmtUsd(e.value), style: atlMono(size: 12, color: atl.text)),
                    ]),
                  )),
            ],

            if (usage.resetEvents.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Recent resets',
                  style: atlSans(size: 12, color: atl.text3, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...usage.resetEvents.take(5).map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Icon(Icons.check_circle_outline, size: 13, color: atl.text3),
                      const SizedBox(width: 6),
                      Text('${r.window == 'week' ? 'Weekly' : 'Session'} limit',
                          style: atlSans(size: 12, color: atl.text2)),
                      const Spacer(),
                      Text(_fmtAgo(r.atTime), style: atlSans(size: 11, color: atl.text3)),
                    ]),
                  )),
            ],
          ],
        ],
      ),
    );
  }

  Widget _bar(AtlColors atl, String label, int pct, DateTime? resetsAt) {
    final limited = pct >= 100;
    final color = limited ? Colors.redAccent.shade200 : (pct >= 80 ? atl.accent : atl.accentInk);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: atlSans(size: 13, color: atl.text, weight: FontWeight.w600)),
          const Spacer(),
          Text('$pct% used',
              style: atlSans(
                  size: 13,
                  color: limited ? Colors.redAccent.shade200 : atl.text2,
                  weight: limited ? FontWeight.w700 : FontWeight.w400)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: atl.surface2,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        if (resetsAt != null) ...[
          const SizedBox(height: 5),
          Text('Resets in ${_fmtCountdown(resetsAt)}',
              style: atlSans(size: 11, color: atl.text3)),
        ],
      ],
    );
  }

  Widget _stat(AtlColors atl, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: atlSans(size: 20, color: atl.text, weight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: atlSans(size: 12, color: atl.text3)),
      ],
    );
  }
}

DateTime _toTime(double epochSeconds) =>
    DateTime.fromMillisecondsSinceEpoch((epochSeconds * 1000).round());

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
