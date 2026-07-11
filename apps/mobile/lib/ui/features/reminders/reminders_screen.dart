import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/jobs_repository.dart';
import '../../../data/services/reminder_service.dart';
import '../../../domain/models/cron_job.dart';
import '../../../domain/models/local_reminder.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';

/// Opens the Reminders page.
Future<void> openReminders(BuildContext context) {
  final reminders = context.read<ReminderService>();
  final jobs = context.read<JobsRepository>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: reminders),
          Provider.value(value: jobs),
        ],
        child: const RemindersScreen(),
      ),
    ),
  );
}

/// Two kinds of reminders:
/// • Alarms — on-device local notifications that fire at an exact time, offline.
/// • Agent tasks — server-side cron jobs that run a prompt on the gateway.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late Future<List<CronJob>> _jobs;

  @override
  void initState() {
    super.initState();
    _jobs = context.read<JobsRepository>().list();
  }

  void _reloadJobs() => setState(() => _jobs = context.read<JobsRepository>().list());

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final reminders = context.watch<ReminderService>().reminders;

    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: atl.text,
          title: Text('Reminders', style: atlSans(size: 18, color: atl.text, weight: FontWeight.w600)),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
            children: [
              _sectionHeader(atl, 'Alarms', 'On this device · fire offline', Icons.alarm,
                  onAdd: _addAlarm),
              const SizedBox(height: 10),
              if (reminders.isEmpty)
                _hint(atl, 'No alarms. Tap + to add one.')
              else
                for (final r in reminders) _alarmCard(atl, r),
              const SizedBox(height: 26),
              _sectionHeader(atl, 'Agent tasks', 'Run on the gateway on a schedule',
                  Icons.smart_toy_outlined,
                  onAdd: _addJob),
              const SizedBox(height: 10),
              FutureBuilder<List<CronJob>>(
                future: _jobs,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  if (snap.hasError) {
                    return _hint(atl, 'Could not load tasks: ${snap.error}');
                  }
                  final jobs = snap.data ?? const [];
                  if (jobs.isEmpty) return _hint(atl, 'No scheduled tasks. Tap + to add one.');
                  return Column(children: [for (final j in jobs) _jobCard(atl, j)]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(AtlColors atl, String title, String subtitle, IconData icon,
          {required VoidCallback onAdd}) =>
      Row(
        children: [
          Icon(icon, size: 20, color: atl.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: atlSans(size: 17, color: atl.text, weight: FontWeight.w700)),
                Text(subtitle, style: atlSans(size: 12, color: atl.text3)),
              ],
            ),
          ),
          Pressable(
            onTap: onAdd,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: atl.accentSoft,
                shape: BoxShape.circle,
                border: Border.all(color: atl.accent),
              ),
              child: Icon(Icons.add, size: 20, color: atl.accent),
            ),
          ),
        ],
      );

  Widget _alarmCard(AtlColors atl, LocalReminder r) {
    final time = TimeOfDay.fromDateTime(r.time).format(context);
    final when = r.repeatDaily
        ? 'Daily · $time'
        : '${_dateLabel(r.time)} · $time';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title, style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(when, style: atlSans(size: 12, color: atl.text2)),
              ],
            ),
          ),
          Pressable(
            onTap: () => context.read<ReminderService>().remove(r.id),
            child: Icon(Icons.delete_outline, size: 20, color: atl.text3),
          ),
        ],
      ),
    );
  }

  Widget _jobCard(AtlColors atl, CronJob j) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(j.name,
                    style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
              ),
              if (j.isPaused)
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
          const SizedBox(height: 3),
          Text(j.scheduleDisplay, style: atlMono(size: 12, color: atl.text2)),
          if (j.prompt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(j.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: atlSans(size: 13, color: atl.text3)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _jobBtn(atl, j.isPaused ? Icons.play_arrow : Icons.pause,
                  j.isPaused ? 'Resume' : 'Pause', () async {
                final repo = context.read<JobsRepository>();
                j.isPaused ? await repo.resume(j.id) : await repo.pause(j.id);
                _reloadJobs();
              }),
              const SizedBox(width: 8),
              _jobBtn(atl, Icons.bolt, 'Run', () async {
                await context.read<JobsRepository>().run(j.id);
                if (mounted) _snack('Triggered "${j.name}"');
              }),
              const SizedBox(width: 8),
              _jobBtn(atl, Icons.delete_outline, 'Delete', () async {
                await context.read<JobsRepository>().delete(j.id);
                _reloadJobs();
              }, danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _jobBtn(AtlColors atl, IconData icon, String label, VoidCallback onTap,
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
                      size: 11, color: danger ? AtlColors.danger : atl.text2, weight: FontWeight.w500)),
            ],
          ),
        ),
      );

  Widget _hint(AtlColors atl, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: atlSans(size: 13, color: atl.text3)),
      );

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = that.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '${d.month}/${d.day}';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- add flows -------------------------------------------------------------

  Future<void> _addAlarm() async {
    final titleC = TextEditingController();
    bool repeat = false;
    TimeOfDay picked = TimeOfDay.now();
    final atl = context.atl;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: _sheet(atl, 'New alarm', [
            _textField(atl, titleC, 'What to remind you', 'e.g. Stand up and stretch'),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Time', style: atlSans(size: 13, color: atl.text2, weight: FontWeight.w600)),
                const Spacer(),
                Pressable(
                  onTap: () async {
                    final t = await showTimePicker(context: sheetCtx, initialTime: picked);
                    if (t != null) setSheet(() => picked = t);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: atl.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: atl.hairline),
                    ),
                    child: Text(picked.format(sheetCtx),
                        style: atlMono(size: 15, color: atl.text)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Repeat daily', style: atlSans(size: 13, color: atl.text2, weight: FontWeight.w600)),
                const Spacer(),
                Switch.adaptive(
                  value: repeat,
                  onChanged: (v) => setSheet(() => repeat = v),
                  activeThumbColor: atl.accent,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _primaryButton(atl, 'Set alarm', () async {
              final title = titleC.text.trim();
              if (title.isEmpty) return;
              final now = DateTime.now();
              var when = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
              if (!repeat && when.isBefore(now)) {
                when = when.add(const Duration(days: 1)); // next occurrence
              }
              final ok = await context.read<ReminderService>().add(
                  title: title, time: when, repeatDaily: repeat);
              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              if (!ok && mounted) _snack('Pick a future time');
            }),
          ]),
        ),
      ),
    );
  }

  Future<void> _addJob() async {
    final nameC = TextEditingController();
    final promptC = TextEditingController();
    String schedule = '0 8 * * *'; // daily 8am default
    final atl = context.atl;
    const presets = {
      'Every hour': '0 * * * *',
      'Daily 8am': '0 8 * * *',
      'Daily 9pm': '0 21 * * *',
      'Weekdays 8am': '0 8 * * 1-5',
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: _sheet(atl, 'New agent task', [
            _textField(atl, nameC, 'Name', 'e.g. Morning briefing'),
            const SizedBox(height: 12),
            _textField(atl, promptC, 'Prompt for the agent',
                'e.g. Summarize my calendar and unread items', maxLines: 3),
            const SizedBox(height: 14),
            Text('Schedule', style: atlSans(size: 13, color: atl.text2, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in presets.entries)
                  Pressable(
                    onTap: () => setSheet(() => schedule = e.value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: schedule == e.value ? atl.accent : atl.surface2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: schedule == e.value ? atl.accent : atl.hairline),
                      ),
                      child: Text(e.key,
                          style: atlSans(
                              size: 12,
                              color: schedule == e.value ? atl.accentInk : atl.text2,
                              weight: FontWeight.w500)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('cron: $schedule', style: atlMono(size: 11, color: atl.text3)),
            const SizedBox(height: 12),
            _primaryButton(atl, 'Create task', () async {
              final name = nameC.text.trim();
              final prompt = promptC.text.trim();
              if (name.isEmpty || prompt.isEmpty) return;
              try {
                await context.read<JobsRepository>().create(
                    name: name, schedule: schedule, prompt: prompt);
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                _reloadJobs();
              } catch (e) {
                if (mounted) _snack('Create failed: $e');
              }
            }),
          ]),
        ),
      ),
    );
  }

  Widget _sheet(AtlColors atl, String title, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: atl.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: atlSerif(size: 22, color: atl.text)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _textField(AtlColors atl, TextEditingController c, String label, String hint,
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

  Widget _primaryButton(AtlColors atl, String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(label,
                style: atlSans(size: 15, color: const Color(0xFF0A0A14), weight: FontWeight.w600)),
          ),
        ),
      );
}
