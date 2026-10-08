import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/jobs_repository.dart';
import '../../../domain/models/cron_job.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import 'automations_view_model.dart';
import 'schedule_parser.dart';

/// Opens the Automations screen (server-side scheduled agent routines).
Future<void> openAutomationsScreen(BuildContext context) {
  final jobs = context.read<JobsRepository>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => AutomationsViewModel(jobs)..load(),
        child: const AutomationsScreen(),
      ),
    ),
  );
}

/// A quick-start template that prefills the new-routine sheet.
class _Template {
  const _Template(this.label, this.icon, this.name, this.prompt, this.cron, this.when);
  final String label;
  final IconData icon;
  final String name;
  final String prompt;
  final String cron;
  final String when;
}

const _templates = <_Template>[
  _Template(
    'Morning Brief',
    Icons.wb_sunny_outlined,
    'Morning Brief',
    "Give me a concise morning briefing: today's calendar, important unread "
        'email, and anything I should know.',
    '0 8 * * *',
    'Daily at 8:00 AM',
  ),
  _Template(
    'Evening Recap',
    Icons.nightlight_outlined,
    'Evening Recap',
    "Summarize what happened today and what's on tomorrow's calendar.",
    '0 21 * * *',
    'Daily at 9:00 PM',
  ),
  _Template(
    'Hourly Check',
    Icons.hourglass_empty,
    'Hourly Check',
    'Check for anything urgent in email or calendar and tell me only if '
        'something needs my attention.',
    '0 * * * *',
    'Every hour',
  ),
  _Template(
    'Weekday Standup',
    Icons.work_outline,
    'Weekday Standup',
    "Give me a weekday standup: today's meetings and my top priorities.",
    '0 9 * * 1-5',
    'Weekdays at 9:00 AM',
  ),
];

/// Server-side scheduled agent routines. Unlike on-device alarms, these run on
/// the gateway on a schedule even when the app is closed.
class AutomationsScreen extends StatelessWidget {
  const AutomationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<AutomationsViewModel>();

    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: atl.text,
          title: Text('Automations',
              style: atlSans(size: 18, color: atl.text, weight: FontWeight.w600)),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openCreateSheet(context),
          backgroundColor: atl.accent,
          foregroundColor: atl.accentInk,
          icon: const Icon(Icons.add),
          label: Text('New routine',
              style: atlSans(size: 14, color: atl.accentInk, weight: FontWeight.w600)),
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: vm.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 96),
              children: [
                Text(
                  'Routines run on your Hermes gateway on a schedule — even when '
                  'the app is closed.',
                  style: atlSans(size: 13, color: atl.text3, height: 1.4),
                ),
                const SizedBox(height: 18),
                if (vm.loading && vm.jobs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (vm.error != null && vm.jobs.isEmpty)
                  _hint(atl, 'Could not load routines: ${vm.error}')
                else if (vm.jobs.isEmpty)
                  _emptyState(context, atl)
                else
                  for (final j in vm.jobs) _JobCard(job: j),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, AtlColors atl) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hint(atl, 'No routines yet. Start from a template:'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _templates)
                Pressable(
                  onTap: () => _openCreateSheet(context, template: t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: atl.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: atl.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 16, color: atl.accent),
                        const SizedBox(width: 7),
                        Text(t.label,
                            style: atlSans(size: 13, color: atl.text, weight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );

  Widget _hint(AtlColors atl, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: atlSans(size: 13, color: atl.text3)),
      );

  Future<void> _openCreateSheet(BuildContext context, {_Template? template}) {
    final vm = context.read<AutomationsViewModel>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: _CreateRoutineSheet(template: template),
      ),
    );
  }
}

/// One routine card with pause/resume, run-now and delete controls.
class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final CronJob job;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.read<AutomationsViewModel>();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(job.name,
                    style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
              ),
              if (job.isPaused)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: atl.surface2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Paused', style: atlSans(size: 10, color: atl.text3)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.schedule, size: 13, color: atl.text3),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  job.scheduleDisplay.isEmpty ? '—' : job.scheduleDisplay,
                  style: atlMono(size: 12, color: atl.text2),
                ),
              ),
            ],
          ),
          if (job.prompt.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(job.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: atlSans(size: 13, color: atl.text3)),
          ],
          if (job.nextRunAt != null || job.lastRunAt != null) ...[
            const SizedBox(height: 6),
            Text(
              _runSummary(job),
              style: atlSans(size: 11, color: atl.text3),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _btn(atl, job.isPaused ? Icons.play_arrow : Icons.pause,
                  job.isPaused ? 'Resume' : 'Pause',
                  () => vm.setPaused(job, !job.isPaused)),
              const SizedBox(width: 8),
              _btn(atl, Icons.bolt, 'Run now', () async {
                final err = await vm.runNow(job);
                if (context.mounted) {
                  _snack(context, err == null ? 'Triggered "${job.name}"' : 'Run failed: $err');
                }
              }),
              const SizedBox(width: 8),
              _btn(atl, Icons.delete_outline, 'Delete',
                  () => _confirmDelete(context, vm), danger: true),
            ],
          ),
        ],
      ),
    );
  }

  String _runSummary(CronJob job) {
    final parts = <String>[];
    if (job.nextRunAt != null) parts.add('Next ${_rel(job.nextRunAt!)}');
    if (job.lastRunAt != null) {
      final status = (job.lastStatus ?? '').isEmpty ? '' : ' (${job.lastStatus})';
      parts.add('Last ${_rel(job.lastRunAt!)}$status');
    }
    return parts.join(' · ');
  }

  Future<void> _confirmDelete(BuildContext context, AutomationsViewModel vm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete routine?'),
        content: Text('"${job.name}" will stop running.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await vm.delete(job);
  }

  Widget _btn(AtlColors atl, IconData icon, String label, VoidCallback onTap,
          {bool danger = false}) =>
      Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: atl.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: atl.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: danger ? AtlColors.danger : atl.text2),
              const SizedBox(width: 4),
              Text(label,
                  style: atlSans(
                      size: 11,
                      color: danger ? AtlColors.danger : atl.text2,
                      weight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

/// Relative time like "in 2h", "3d ago". Keeps the card compact.
String _rel(DateTime t) {
  final now = DateTime.now();
  final future = t.isAfter(now);
  final d = (future ? t.difference(now) : now.difference(t)).abs();
  String mag;
  if (d.inMinutes < 1) {
    mag = 'now';
    return mag;
  } else if (d.inMinutes < 60) {
    mag = '${d.inMinutes}m';
  } else if (d.inHours < 24) {
    mag = '${d.inHours}h';
  } else {
    mag = '${d.inDays}d';
  }
  return future ? 'in $mag' : '$mag ago';
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Bottom sheet to create a routine: templates, name/prompt, natural-language
/// scheduling with a live cron preview (with preset-chip fallback), and where to
/// deliver the result.
class _CreateRoutineSheet extends StatefulWidget {
  const _CreateRoutineSheet({this.template});
  final _Template? template;

  @override
  State<_CreateRoutineSheet> createState() => _CreateRoutineSheetState();
}

class _CreateRoutineSheetState extends State<_CreateRoutineSheet> {
  late final TextEditingController _nameC;
  late final TextEditingController _promptC;
  final _whenC = TextEditingController();

  String _cron = '0 8 * * *';
  String _whenLabel = 'Daily at 8:00 AM';
  String? _whenError; // set when the typed phrase couldn't be parsed
  String _deliver = 'local';
  bool _saving = false;

  static const _presets = <String, (String, String)>{
    'Every hour': ('0 * * * *', 'Every hour'),
    'Daily 8am': ('0 8 * * *', 'Daily at 8:00 AM'),
    'Daily 9pm': ('0 21 * * *', 'Daily at 9:00 PM'),
    'Weekdays 9am': ('0 9 * * 1-5', 'Weekdays at 9:00 AM'),
  };

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _nameC = TextEditingController(text: t?.name ?? '');
    _promptC = TextEditingController(text: t?.prompt ?? '');
    if (t != null) {
      _cron = t.cron;
      _whenLabel = t.when;
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _promptC.dispose();
    _whenC.dispose();
    super.dispose();
  }

  void _onWhenChanged(String value) {
    if (value.trim().isEmpty) {
      setState(() => _whenError = null);
      return;
    }
    final parsed = parseSchedule(value);
    setState(() {
      if (parsed != null) {
        _cron = parsed.cron;
        _whenLabel = parsed.display;
        _whenError = null;
      } else {
        _whenError = "Couldn't read that — try a chip below.";
      }
    });
  }

  void _selectPreset(String cron, String label) {
    setState(() {
      _cron = cron;
      _whenLabel = label;
      _whenError = null;
      _whenC.clear();
    });
  }

  Future<void> _create() async {
    final name = _nameC.text.trim();
    final prompt = _promptC.text.trim();
    if (name.isEmpty || prompt.isEmpty) {
      _snack(context, 'Add a name and a prompt.');
      return;
    }
    setState(() => _saving = true);
    final vm = context.read<AutomationsViewModel>();
    final err = await vm.create(
      name: name,
      schedule: _cron,
      prompt: prompt,
      deliver: _deliver,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err == null) {
      Navigator.pop(context);
    } else {
      _snack(context, 'Create failed: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: atl.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New routine', style: atlSerif(size: 22, color: atl.text)),
              const SizedBox(height: 14),

              // Templates
              Text('Start from a template',
                  style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _templates)
                    Pressable(
                      onTap: () {
                        setState(() {
                          _nameC.text = t.name;
                          _promptC.text = t.prompt;
                          _cron = t.cron;
                          _whenLabel = t.when;
                          _whenError = null;
                          _whenC.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          color: atl.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: atl.hairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.icon, size: 15, color: atl.accent),
                            const SizedBox(width: 6),
                            Text(t.label, style: atlSans(size: 12, color: atl.text)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              _field(atl, _nameC, 'Name', 'e.g. Morning briefing'),
              const SizedBox(height: 12),
              _field(atl, _promptC, 'What should Hermes do?',
                  'e.g. Summarize my calendar and unread email', maxLines: 3),
              const SizedBox(height: 14),

              // Natural-language schedule
              Text('When', style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _whenC,
                onChanged: _onWhenChanged,
                style: atlSans(size: 15, color: atl.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. every weekday at 9am',
                  hintStyle: atlSans(size: 14, color: atl.text3),
                  filled: true,
                  fillColor: atl.surface2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: atl.fieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: atl.fieldBorder),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _presets.entries)
                    Pressable(
                      onTap: () => _selectPreset(e.value.$1, e.value.$2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _cron == e.value.$1 ? atl.accent : atl.surface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _cron == e.value.$1 ? atl.accent : atl.hairline),
                        ),
                        child: Text(e.key,
                            style: atlSans(
                                size: 12,
                                color: _cron == e.value.$1 ? atl.accentInk : atl.text2,
                                weight: FontWeight.w500)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_whenError != null)
                Text(_whenError!, style: atlSans(size: 11, color: AtlColors.danger))
              else
                Text('Runs: $_whenLabel   ·   cron: $_cron',
                    style: atlMono(size: 11, color: atl.text3)),
              const SizedBox(height: 16),

              // Delivery
              Text('Deliver result',
                  style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _deliverPill(atl, 'In app', Icons.phone_iphone, 'local'),
                  const SizedBox(width: 8),
                  _deliverPill(atl, 'Push notification', Icons.notifications_none, 'ntfy'),
                ],
              ),
              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: Pressable(
                  onTap: _saving ? null : _create,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF0A0A14)),
                          )
                        : Text('Create routine',
                            style: atlSans(
                                size: 15,
                                color: const Color(0xFF0A0A14),
                                weight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deliverPill(AtlColors atl, String label, IconData icon, String value) {
    final selected = _deliver == value;
    return Expanded(
      child: Pressable(
        onTap: () => setState(() => _deliver = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? atl.accentSoft : atl.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? atl.accent : atl.hairline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? atl.accent : atl.text2),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: atlSans(
                        size: 12,
                        color: selected ? atl.accent : atl.text2,
                        weight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(AtlColors atl, TextEditingController c, String label, String hint,
          {int maxLines = 1}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            maxLines: maxLines,
            style: atlSans(size: 15, color: atl.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: atlSans(size: 14, color: atl.text3),
              filled: true,
              fillColor: atl.surface2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: atl.fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: atl.fieldBorder),
              ),
            ),
          ),
        ],
      );
}
