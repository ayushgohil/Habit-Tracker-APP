/// What the card-style home-screen widgets show about one habit, worked out
/// from its history. Pure data, so it can be tested without drawing anything.
library;

import '../core/day.dart';
import '../core/streak.dart';
import '../core/timer.dart';
import '../data/providers.dart';

/// The kinds of card widget, in the order they are offered.
enum CardKind { streak, ring, week, trend, month, grid }

/// One day in the month calendar.
enum DotState { done, missed, today, upcoming, off }

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Days shown on the trend chart.
const trendDays = 30;

class CardHabit {
  const CardHabit({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.progress,
    required this.done,
    required this.tappable,
    required this.streakLength,
    required this.streakNoun,
    required this.countText,
    required this.week,
    required this.trend,
    required this.trendFrom,
    required this.month,
  });

  final int id;
  final String name;
  final String iconKey;
  final int colorValue;

  /// Today's progress from 0 to 1, and whether the day is done.
  final double progress;
  final bool done;

  /// Whether tapping the widget can log the habit without opening the app.
  final bool tappable;

  final int streakLength;

  /// "day", "week", ... the unit the streak is counted in.
  final String streakNoun;

  /// "750/2000", or empty for a plain habit.
  final String countText;

  /// Monday to Sunday of this week: the share of the goal reached, or null for
  /// days that have not happened yet.
  final List<double?> week;

  /// The last [trendDays] days ending today, each as a share of the goal.
  final List<double> trend;

  /// Label for the first day of [trend], like "22 Oct 26".
  final String trendFrom;

  /// This month laid out in Monday-first weeks. Null cells are outside the month.
  final List<DotState?> month;

  /// Everything that changes what is drawn, so a redraw can be skipped when it is the same.
  String get fingerprint => [
        id, name, iconKey, colorValue, progress.toStringAsFixed(3), done, tappable, streakLength, streakNoun,
        countText, week.map((v) => v?.toStringAsFixed(2) ?? '-').join(','),
        trend.map((v) => v.toStringAsFixed(2)).join(','), trendFrom, month.map((s) => s?.index ?? -1).join(','),
      ].join('|');
}

String _dayLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${(d.year % 100).toString().padLeft(2, '0')}';

CardHabit buildCardHabit(HabitView view, HabitHistory history, DateTime today) {
  final habit = view.habit;
  final amounts = history.amounts;

  double share(DateTime day) {
    if (habit.limitMode) return history.doneDays.contains(dayKey(day)) ? 1.0 : 0.0;
    final target = history.targetOn(day);
    if (target <= 0) return 0.0;
    return ((amounts[dayKey(day)] ?? 0) / target).clamp(0.0, 1.0).toDouble();
  }

  final monday = startOfWeek(today);
  final week = <double?>[
    for (var i = 0; i < 7; i++) addDays(monday, i).isAfter(today) ? null : share(addDays(monday, i)),
  ];
  final from = addDays(today, -(trendDays - 1));
  final trend = [for (var i = 0; i < trendDays; i++) share(addDays(from, i))];

  final first = DateTime(today.year, today.month);
  final lead = first.weekday - 1;
  final length = DateTime(today.year, today.month + 1, 0).day;
  final cells = <DotState?>[];
  for (var i = 0; i < ((lead + length + 6) ~/ 7) * 7; i++) {
    if (i < lead || i >= lead + length) {
      cells.add(null);
      continue;
    }
    final day = addDays(first, i - lead);
    if (history.doneDays.contains(dayKey(day))) {
      cells.add(DotState.done);
    } else if (day == startOfDay(today)) {
      cells.add(DotState.today);
    } else if (day.isAfter(today)) {
      cells.add(DotState.upcoming);
    } else if (!history.scheduleOn(day).isDue(day)) {
      cells.add(DotState.off);
    } else {
      cells.add(DotState.missed);
    }
  }

  final timed = habit.taskType == HabitTaskType.timed.index;
  final String countText;
  if (habit.limitMode) {
    countText = '${formatClock(view.countToday)} used';
  } else if (timed) {
    countText = '${view.countToday ~/ 60}/${view.target ~/ 60} min';
  } else if (view.target > 1) {
    final unit = habit.unitLabel.trim();
    countText = unit.isEmpty ? '${view.countToday}/${view.target}' : '${view.countToday}/${view.target} $unit';
  } else {
    countText = '';
  }

  return CardHabit(
    id: habit.id,
    name: habit.name,
    iconKey: habit.iconKey,
    colorValue: habit.colorValue,
    progress: view.progress,
    done: view.isDone,
    tappable: !timed && habit.healthMetric == 0,
    streakLength: view.streak.length,
    streakNoun: switch (view.streak.unit) {
      StreakUnit.days => 'day',
      StreakUnit.weeks => 'week',
      StreakUnit.fortnights => 'fortnight',
      StreakUnit.months => 'month',
      StreakUnit.years => 'year',
    },
    countText: countText,
    week: week,
    trend: trend,
    trendFrom: _dayLabel(from),
    month: cells,
  );
}
