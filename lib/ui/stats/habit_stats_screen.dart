import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/day.dart';
import '../../core/history.dart';
import '../../core/habit_icons.dart';
import '../../core/streak.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';
import '../common/text_dialogs.dart';
import 'bar_chart.dart';

enum _Range { week, month, year }

class HabitStatsScreen extends ConsumerStatefulWidget {
  const HabitStatsScreen({super.key, required this.habitId});
  final int habitId;

  @override
  ConsumerState<HabitStatsScreen> createState() => _HabitStatsScreenState();
}

class _HabitStatsScreenState extends ConsumerState<HabitStatsScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  _Range _range = _Range.week;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(habitHistoryProvider(widget.habitId));
    if (history == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stats')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final habit = history.habit;
    final color = Color(habit.colorValue);
    final today = startOfDay(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(habitIconFor(habit.iconKey), color: color, size: 22),
            const SizedBox(width: 10),
            Flexible(child: Text(habit.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _StatsGrid(history: history),
          const SizedBox(height: 24),
          _CalendarCard(
            history: history,
            month: _month,
            today: today,
            color: color,
            onMonthChanged: (m) => setState(() => _month = m),
            onDayTap: (day) => _onDayTap(history, day),
          ),
          const SizedBox(height: 24),
          _ChartCard(
            history: history,
            range: _range,
            today: today,
            color: color,
            onRange: (r) => setState(() => _range = r),
          ),
        ],
      ),
    );
  }

  Future<void> _onDayTap(HabitHistory history, DateTime day) async {
    final today = startOfDay(DateTime.now());
    if (day.isAfter(today) || day.isBefore(startOfDay(history.habit.createdAt))) return;
    final actions = ref.read(habitActionsProvider);
    final current = history.amounts[dayKey(day)] ?? 0;
    final timed = history.habit.taskType == HabitTaskType.timed.index;
    if (timed) {
      final minutes = await showLogTimeDialog(
        context,
        habitName: history.habit.name,
        canClear: current > 0,
      );
      if (minutes == null) return;
      await actions.setDayAmount(
        history.habit.id,
        day,
        minutes == clearLoggedTime ? 0 : current + minutes * 60,
      );
    } else {
      final done = current >= history.target;
      await actions.setDayAmount(history.habit.id, day, done ? 0 : current + 1);
    }
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.history});
  final HabitHistory history;

  @override
  Widget build(BuildContext context) {
    final stats = history.stats;
    final tiles = <(String, String)>[
      ('Current streak', stats.currentStreak.longLabel),
      ('Best streak', stats.bestStreak.longLabel),
      ('Completion', '${(stats.completionRate * 100).round()}%'),
      ('Total done', '${history.totalDone}'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.1,
      children: [
        for (final t in tiles)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EmberColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.$1, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: EmberColors.textMuted)),
                const SizedBox(height: 2),
                Text(t.$2, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
      ],
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.history,
    required this.month,
    required this.today,
    required this.color,
    required this.onMonthChanged,
    required this.onDayTap,
  });

  final HabitHistory history;
  final DateTime month;
  final DateTime today;
  final Color color;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final grid = monthGrid(month);
    final start = startOfDay(history.habit.createdAt);
    final canGoBack = DateTime(month.year, month.month).isAfter(DateTime(start.year, start.month));
    final canGoForward = DateTime(month.year, month.month).isBefore(DateTime(today.year, today.month));
    final doneThisMonth = doneDaysInMonth(history.doneDays, month);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: EmberColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('calendar-prev'),
                onPressed: canGoBack ? () => onMonthChanged(DateTime(month.year, month.month - 1)) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(DateFormat('MMMM yyyy').format(month), style: Theme.of(context).textTheme.titleMedium),
                    Text('$doneThisMonth done', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: EmberColors.textMuted)),
                  ],
                ),
              ),
              IconButton(
                key: const Key('calendar-next'),
                onPressed: canGoForward ? () => onMonthChanged(DateTime(month.year, month.month + 1)) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final name in weekdayShortNames)
                Expanded(
                  child: Center(
                    child: Text(name.substring(0, 1), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: EmberColors.textMuted)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final week in grid)
            Row(
              children: [
                for (final day in week)
                  Expanded(
                    child: day == null
                        ? const SizedBox(height: 44)
                        : _DayCell(
                            day: day,
                            state: dayStateFor(
                              schedule: history.schedule,
                              amount: history.amounts[dayKey(day)] ?? 0,
                              target: history.target,
                              day: day,
                              today: today,
                              start: start,
                            ),
                            isToday: day == today,
                            color: color,
                            onTap: () => onDayTap(day),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.state,
    required this.isToday,
    required this.color,
    required this.onTap,
  });

  final DateTime day;
  final DayState state;
  final bool isToday;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = state == DayState.beforeStart || state == DayState.future;
    final Color fill;
    final Color text;
    switch (state) {
      case DayState.done:
        fill = color;
        text = EmberColors.onEmber;
      case DayState.partial:
        fill = color.withValues(alpha: .35);
        text = EmberColors.text;
      case DayState.missed:
        fill = EmberColors.surfaceHigh;
        text = EmberColors.text;
      default:
        fill = Colors.transparent;
        text = inactive ? EmberColors.textMuted.withValues(alpha: .4) : EmberColors.textMuted;
    }
    return GestureDetector(
      key: Key('day-${dayKey(day)}'),
      behavior: HitTestBehavior.opaque,
      onTap: inactive ? null : onTap,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: isToday ? Border.all(color: color, width: 2) : null,
            ),
            child: Text('${day.day}', style: TextStyle(color: text, fontWeight: state == DayState.done ? FontWeight.w700 : FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.history,
    required this.range,
    required this.today,
    required this.color,
    required this.onRange,
  });

  final HabitHistory history;
  final _Range range;
  final DateTime today;
  final Color color;
  final ValueChanged<_Range> onRange;

  @override
  Widget build(BuildContext context) {
    final List<double> values;
    final List<String> labels;
    final double maxValue;
    var every = 1;
    switch (range) {
      case _Range.week:
        values = dailyProgress(amounts: history.amounts, target: history.target, end: today, days: 7);
        labels = [for (var i = 6; i >= 0; i--) DateFormat('E').format(addDays(today, -i)).substring(0, 1)];
        maxValue = 1;
      case _Range.month:
        values = dailyProgress(amounts: history.amounts, target: history.target, end: today, days: 30);
        labels = [for (var i = 29; i >= 0; i--) '${addDays(today, -i).day}'];
        maxValue = 1;
        every = 5;
      case _Range.year:
        final counts = doneDaysPerMonth(doneDays: history.doneDays, end: today, months: 12);
        values = [for (final c in counts) c.toDouble()];
        labels = [for (var i = 11; i >= 0; i--) DateFormat('MMM').format(DateTime(today.year, today.month - i)).substring(0, 1)];
        maxValue = 31;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: EmberColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(range == _Range.year ? 'Days done per month' : 'Progress per day', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SegmentedButton<_Range>(
            segments: const [
              ButtonSegment(value: _Range.week, label: Text('Week')),
              ButtonSegment(value: _Range.month, label: Text('Month')),
              ButtonSegment(value: _Range.year, label: Text('Year')),
            ],
            selected: {range},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onRange(s.first),
          ),
          const SizedBox(height: 16),
          EmberBarChart(
            key: Key('chart-${range.name}'),
            values: values,
            labels: labels,
            maxValue: maxValue,
            color: color,
            labelEvery: every,
          ),
        ],
      ),
    );
  }
}
