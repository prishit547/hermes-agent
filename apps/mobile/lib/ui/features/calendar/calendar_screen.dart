import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/calendar_event.dart';
import '../../core/animations.dart';
import '../../core/atl_theme.dart';
import '../reminders/reminders_screen.dart';
import 'calendar_view_model.dart';

/// Agenda view. Aggregates Google Calendar events (fetched through the agent),
/// server agent tasks, and on-device alarms into one timeline. The
/// natural-language add field sends the event to the agent, which schedules it
/// via the `google_calendar` tool.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _addController = TextEditingController();
  bool _adding = false;

  DateTime _currentMonth = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> _daysInMonthGrid(DateTime monthDate) {
    final firstDayOfMonth = DateTime(monthDate.year, monthDate.month, 1);
    final startOffset = firstDayOfMonth.weekday % 7;
    final startDate = firstDayOfMonth.subtract(Duration(days: startOffset));
    return List.generate(42, (idx) => startDate.add(Duration(days: idx)));
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
  }

  @override
  void initState() {
    super.initState();
    final vm = context.read<CalendarViewModel>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      vm.loadIfNeeded();
    });
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _submitAdd(CalendarViewModel vm) async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    setState(() => _adding = true);
    final ok = await vm.addNatural(text);
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok) {
      _addController.clear();
      await vm.load();
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(vm.error ?? 'Could not add event')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<CalendarViewModel>();
    final byDay = vm.byDay;
    final selectedDayZero = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    final dayEvents = byDay[selectedDayZero] ?? [];

    return RefreshIndicator(
      onRefresh: () async {
        await vm.load();
        await vm.loadTasks();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: atl.text),
                    onPressed: _prevMonth,
                  ),
                  Text(
                    '${_months[_currentMonth.month - 1]} ${_currentMonth.year}',
                    style: atlSerif(size: 22, color: atl.text),
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right, color: atl.text),
                    onPressed: _nextMonth,
                  ),
                ],
              ),
              Pressable(
                onTap: () => openReminders(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: atl.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: atl.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alarm, size: 15, color: atl.text2),
                      const SizedBox(width: 5),
                      Text('Reminders',
                          style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Visual Calendar Grid
          _calendarGrid(atl, vm),
          const SizedBox(height: 16),

          // Natural-language add → agent
          Container(
            padding: const EdgeInsets.fromLTRB(15, 4, 6, 4),
            decoration: BoxDecoration(
              color: atl.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: atl.fieldBorder),
              boxShadow: atl.cardShadow,
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: atl.accent),
                const SizedBox(width: 11),
                Expanded(
                  child: TextField(
                    controller: _addController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitAdd(vm),
                    style: atlSans(size: 15, color: atl.text),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '"Lunch with Sam tomorrow 1pm"',
                      hintStyle: atlSans(size: 15, color: atl.text3),
                    ),
                  ),
                ),
                _adding
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : Pressable(
                        onTap: () => _submitAdd(vm),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [AtlColors.halo1, AtlColors.halo2, AtlColors.halo3],
                            ),
                          ),
                          child: const Icon(Icons.arrow_upward, size: 19, color: Color(0xFF0A0A14)),
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (vm.googleState == GoogleCalState.notConnected) _connectBanner(atl),
          if (vm.loading && vm.events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            _dayHeader(atl, _selectedDay),
            const SizedBox(height: 12),
            if (dayEvents.isEmpty)
              _emptyAgenda(atl)
            else
              for (final e in dayEvents) ...[
                _eventRow(atl, e),
                const SizedBox(height: 12),
              ],
          ],
        ],
      ),
    );
  }

  Widget _calendarGrid(AtlColors atl, CalendarViewModel vm) {
    final gridDays = _daysInMonthGrid(_currentMonth);
    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: atl.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: atl.hairline),
        boxShadow: atl.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((day) => Expanded(
              child: Center(
                child: Text(
                  day,
                  style: atlSans(size: 13, color: atl.text3, weight: FontWeight.w600),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: 42,
            itemBuilder: (context, index) {
              final day = gridDays[index];
              final isSelected = _isSameDay(day, _selectedDay);
              final isToday = _isSameDay(day, DateTime.now());
              final isCurrentMonth = day.month == _currentMonth.month && day.year == _currentMonth.year;
              final hasEvents = vm.byDay[DateTime(day.year, day.month, day.day)]?.isNotEmpty ?? false;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDay = day;
                    _currentMonth = DateTime(day.year, day.month);
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? atl.accent
                        : isToday
                            ? atl.accentSoft
                            : Colors.transparent,
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: atlSans(
                          size: 14,
                          color: isSelected
                              ? atl.accentInk
                              : isCurrentMonth
                                  ? atl.text
                                  : atl.text3,
                          weight: (isSelected || isToday) ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (hasEvents)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? atl.accentInk : atl.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _connectBanner(AtlColors atl) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: atl.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: atl.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.link_off, size: 20, color: atl.text3),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Google Calendar not connected',
                      style: atlSans(size: 14, color: atl.text, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Authorize it on your Mac (hermes google-calendar) to sync events. '
                      'Alarms and agent tasks still show below.',
                      style: atlSans(size: 12, color: atl.text3)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _emptyAgenda(AtlColors atl) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_available_outlined, size: 42, color: atl.text3),
              const SizedBox(height: 12),
              Text('Nothing scheduled',
                  style: atlSans(size: 16, color: atl.text, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Add an event above, or set a reminder.',
                  style: atlSans(size: 13, color: atl.text3)),
            ],
          ),
        ),
      );

  Widget _dayHeader(AtlColors atl, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    final label = diff == 0
        ? 'Today'
        : diff == 1
            ? 'Tomorrow'
            : _weekday(day.weekday);
    const monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: atlSans(size: 15, color: atl.text, weight: FontWeight.w700)),
        const SizedBox(width: 9),
        Text('${_weekday(day.weekday).substring(0, 3)}, ${monthsShort[day.month - 1]} ${day.day}',
            style: atlSans(size: 13, color: atl.text3)),
      ],
    );
  }

  Widget _eventRow(AtlColors atl, CalendarEvent e) {
    final color = switch (e.kind) {
      CalendarKind.event => AtlColors.eventBlue,
      CalendarKind.task => AtlColors.eventGold,
      CalendarKind.alarm => AtlColors.eventPink,
    };
    final t = TimeOfDay.fromDateTime(e.start).format(context);
    final parts = t.split(' ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(parts.first, style: atlMono(size: 14, color: atl.text)),
              if (parts.length > 1)
                Text(parts[1], style: atlSans(size: 11, color: atl.text3)),
            ],
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: atl.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: atl.hairline),
              boxShadow: atl.cardShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, color: color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                style: atlSans(size: 15, color: atl.text, weight: FontWeight.w600)),
                            if (e.subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(e.subtitle!, style: atlSans(size: 13, color: atl.text2)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _weekday(int w) => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ][(w - 1) % 7];
}
