/// Pure logic behind the stats screen: what each calendar day looked like, and
/// the series the charts draw. No Flutter or database code, so it is easy to
/// test.
library;

import 'day.dart';
import 'streak.dart';

/// How a single day looks on the habit calendar.
enum DayState {
  /// Before the habit started. Not part of its history.
  beforeStart,

  /// After today.
  future,

  /// A day the habit isn't scheduled (for example a Tuesday for a Mon/Wed/Fri
  /// habit) with nothing logged.
  notScheduled,

  /// Fully done.
  done,

  /// Some progress, but short of the daily target.
  partial,

  /// A scheduled day that has passed with nothing logged.
  missed,

  /// Today, scheduled, and still to do.
  open,

  /// A day with nothing logged on a habit that is judged over a longer period
  /// (weekly, monthly, every N days...), so a single empty day isn't a miss.
  none,
}

/// Works out how [day] looks.
///
/// [amount] is what was logged on that day and [target] what counts as done.
/// Only habits judged day by day (daily and specific weekdays) can have a
/// [DayState.missed] day; for the rest an empty day is just [DayState.none].
DayState dayStateFor({
  required Schedule schedule,
  required int amount,
  required int target,
  required DateTime day,
  required DateTime today,
  required DateTime start,
}) {
  final d = startOfDay(day);
  final t = startOfDay(today);
  if (d.isBefore(startOfDay(start))) return DayState.beforeStart;
  if (d.isAfter(t)) return DayState.future;
  if (target > 0 && amount >= target) return DayState.done;
  if (amount > 0) return DayState.partial;

  final judgedPerDay = schedule.type == ScheduleType.daily ||
      schedule.type == ScheduleType.weekdays;
  if (!judgedPerDay) return d == t ? DayState.open : DayState.none;
  if (!schedule.isDue(d)) return DayState.notScheduled;
  return d == t ? DayState.open : DayState.missed;
}

/// The weeks (Monday first) that cover the month containing [month].
///
/// Every week has seven cells; cells that fall outside the month are null.
List<List<DateTime?>> monthGrid(DateTime month) {
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final leading = DateTime(month.year, month.month).weekday - 1;
  final cells = <DateTime?>[
    for (var i = 0; i < leading; i++) null,
    for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return [
    for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
  ];
}

/// Progress (0 to 1) for each of the [days] days ending on [end], oldest first.
List<double> dailyProgress({
  required Map<String, int> amounts,
  required int target,
  required DateTime end,
  required int days,
}) {
  return [
    for (var i = days - 1; i >= 0; i--)
      target <= 0
          ? 0.0
          : ((amounts[dayKey(addDays(end, -i))] ?? 0) / target)
              .clamp(0.0, 1.0)
              .toDouble(),
  ];
}

/// How many days were done in each of the [months] calendar months ending with
/// the month of [end], oldest first.
List<int> doneDaysPerMonth({
  required Set<String> doneDays,
  required DateTime end,
  required int months,
}) {
  final counts = <String, int>{};
  for (final key in doneDays) {
    final month = key.substring(0, 7);
    counts[month] = (counts[month] ?? 0) + 1;
  }
  return [
    for (var i = months - 1; i >= 0; i--)
      counts[dayKey(DateTime(end.year, end.month - i)).substring(0, 7)] ?? 0,
  ];
}

/// How many of [doneDays] fall in the same month as [day].
int doneDaysInMonth(Set<String> doneDays, DateTime day) {
  final prefix = dayKey(day).substring(0, 7);
  return doneDays.where((key) => key.startsWith(prefix)).length;
}
