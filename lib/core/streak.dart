import 'day.dart';

enum ScheduleType {
  daily,
  weekdays,
  timesPerWeek,
  everyNDays,
  weekly,
  fortnightly,
  monthly,
  yearly,
}

enum StreakUnit { days, weeks, fortnights, months, years }

enum HabitTaskType { normal, negative, timed }

const weekdayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class Schedule {
  const Schedule({
    this.type = ScheduleType.daily,
    this.weekdayMask = allDaysMask,
    this.timesPerWeek = 7,
    this.intervalDays = 2,
    this.periodTarget = 1,
    this.anchorDate,
  });

  static const allDaysMask = 127;
  final ScheduleType type;
  final int weekdayMask;
  final int timesPerWeek;
  final int intervalDays;
  final int periodTarget;
  final DateTime? anchorDate;

  bool isDue(DateTime day) {
    switch (type) {
      case ScheduleType.daily:
      case ScheduleType.timesPerWeek:
      case ScheduleType.weekly:
      case ScheduleType.fortnightly:
      case ScheduleType.monthly:
      case ScheduleType.yearly:
        return true;
      case ScheduleType.weekdays:
        return ((weekdayMask >> (day.weekday - 1)) & 1) == 1;
      case ScheduleType.everyNDays:
        final anchor = startOfDay(anchorDate ?? DateTime(1970, 1, 5));
        return (daysBetween(anchor, day) % _safeInterval) == 0;
    }
  }

  int get _safeInterval => intervalDays < 1 ? 1 : intervalDays;
  int get target => (type == ScheduleType.timesPerWeek
          ? timesPerWeek.clamp(1, 7)
          : periodTarget.clamp(1, 366))
      .toInt();

  String describe() {
    switch (type) {
      case ScheduleType.daily:
        return 'Every day';
      case ScheduleType.weekdays:
        final days = [
          for (var i = 0; i < 7; i++)
            if (((weekdayMask >> i) & 1) == 1) weekdayShortNames[i],
        ];
        return days.isEmpty ? 'No days selected' : days.join(', ');
      case ScheduleType.timesPerWeek:
        return '$target times a week';
      case ScheduleType.everyNDays:
        return 'Every $_safeInterval days';
      case ScheduleType.weekly:
        return target == 1 ? 'Weekly' : '$target times a week';
      case ScheduleType.fortnightly:
        return target == 1 ? 'Every 2 weeks' : '$target times per 2 weeks';
      case ScheduleType.monthly:
        return target == 1 ? 'Monthly' : '$target times a month';
      case ScheduleType.yearly:
        return target == 1 ? 'Yearly' : '$target times a year';
    }
  }
}

class Streak {
  const Streak(this.length, this.unit);
  final int length;
  final StreakUnit unit;
  String get shortLabel => '$length${switch (unit) {
    StreakUnit.days => 'd',
    StreakUnit.weeks => 'w',
    StreakUnit.fortnights => '2w',
    StreakUnit.months => 'm',
    StreakUnit.years => 'y',
  }}';
  String get longLabel {
    final noun = switch (unit) {
      StreakUnit.days => 'day',
      StreakUnit.weeks => 'week',
      StreakUnit.fortnights => 'fortnight',
      StreakUnit.months => 'month',
      StreakUnit.years => 'year',
    };
    return '$length $noun${length == 1 ? '' : 's'}';
  }
}

class HabitStats {
  const HabitStats({
    required this.currentStreak,
    required this.bestStreak,
    required this.completionRate,
    required this.completedPeriods,
    required this.totalPeriods,
  });
  final Streak currentStreak;
  final Streak bestStreak;
  final double completionRate;
  final int completedPeriods;
  final int totalPeriods;
}

class _Period {
  const _Period(this.start, this.end, this.unit);
  final DateTime start;
  final DateTime end;
  final StreakUnit unit;
}

DateTime _monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime _yearStart(DateTime d) => DateTime(d.year);
DateTime _fortnightStart(DateTime d) {
  final anchor = DateTime(1970, 1, 5);
  final fortnights = daysBetween(anchor, startOfWeek(d)) ~/ 14;
  return addDays(anchor, fortnights * 14);
}

_Period _periodFor(Schedule s, DateTime day) {
  final d = startOfDay(day);
  switch (s.type) {
    case ScheduleType.daily:
    case ScheduleType.weekdays:
      return _Period(d, d, StreakUnit.days);
    case ScheduleType.everyNDays:
      final anchor = startOfDay(s.anchorDate ?? DateTime(1970, 1, 5));
      final interval = s.intervalDays < 1 ? 1 : s.intervalDays;
      final index = daysBetween(anchor, d) ~/ interval;
      final start = addDays(anchor, index * interval);
      return _Period(start, addDays(start, interval - 1), StreakUnit.days);
    case ScheduleType.timesPerWeek:
    case ScheduleType.weekly:
      final start = startOfWeek(d);
      return _Period(start, addDays(start, 6), StreakUnit.weeks);
    case ScheduleType.fortnightly:
      final start = _fortnightStart(d);
      return _Period(start, addDays(start, 13), StreakUnit.fortnights);
    case ScheduleType.monthly:
      final start = _monthStart(d);
      return _Period(start, DateTime(start.year, start.month + 1, 0), StreakUnit.months);
    case ScheduleType.yearly:
      final start = _yearStart(d);
      return _Period(start, DateTime(start.year, 12, 31), StreakUnit.years);
  }
}

bool _samePeriod(_Period a, _Period b) => a.start == b.start;

List<_Period> _periods(Schedule schedule, DateTime from, DateTime through) {
  final result = <_Period>[];
  var cursor = startOfDay(from);
  final end = startOfDay(through);
  while (!cursor.isAfter(end) && result.length < 4000) {
    if (schedule.type == ScheduleType.weekdays && !schedule.isDue(cursor)) {
      cursor = addDays(cursor, 1);
      continue;
    }
    final p = _periodFor(schedule, cursor);
    if (result.isEmpty || !_samePeriod(result.last, p)) result.add(p);
    cursor = addDays(p.end, 1);
  }
  return result;
}

bool _periodComplete(Schedule schedule, _Period period, Set<String> doneDays) {
  // An every-N-days window is flexible: doing the habit on any day inside the
  // window counts, not only on the day the window opens.
  final flexible = schedule.type == ScheduleType.everyNDays;
  var count = 0;
  for (var day = period.start; !day.isAfter(period.end); day = addDays(day, 1)) {
    if ((flexible || schedule.isDue(day)) && doneDays.contains(dayKey(day))) {
      count++;
    }
  }
  return count >= schedule.target;
}

HabitStats calculateHabitStats({
  required Schedule schedule,
  required Set<String> doneDays,
  required DateTime createdAt,
  required DateTime today,
  HabitTaskType taskType = HabitTaskType.normal,
  bool twoDayRule = false,
}) {
  final start = startOfDay(createdAt);
  final end = startOfDay(today);
  final periods = _periods(schedule, start, end);
  final completed = periods.map((p) => _periodComplete(schedule, p, doneDays)).toList();
  final total = periods.length;
  final count = completed.where((v) => v).length;

  var best = 0;
  var run = 0;
  for (final ok in completed) {
    if (ok) {
      run++;
      if (run > best) best = run;
    } else if (taskType != HabitTaskType.negative || !twoDayRule) {
      run = 0;
    } else {
      run = (run == 0) ? 0 : run; // one isolated miss is tolerated below
    }
  }

  var current = 0;
  var misses = 0;
  for (var i = completed.length - 1; i >= 0; i--) {
    // A period is open only while it still contains the day being viewed.
    // The last period is not always open: on a day a weekday habit isn't
    // scheduled, the last period is an earlier scheduled day that is over.
    final isCurrent = !periods[i].end.isBefore(end);
    if (completed[i]) {
      current++;
      misses = 0;
    } else if (isCurrent) {
      // The current period is still open; it never breaks today's streak.
      continue;
    } else if (taskType == HabitTaskType.negative && twoDayRule && misses == 0) {
      misses++;
    } else {
      break;
    }
  }

  // Best streak with the 2-day rule: one missed period may sit inside a run,
  // but it does not itself increase the streak length.
  if (taskType == HabitTaskType.negative && twoDayRule) {
    best = 0;
    var successes = 0;
    var missesInRun = 0;
    for (final ok in completed) {
      if (ok) {
        successes++;
        missesInRun = 0;
        if (successes > best) best = successes;
      } else if (successes > 0 && missesInRun == 0) {
        missesInRun = 1;
      } else {
        successes = 0;
        missesInRun = 0;
      }
    }
  }

  final unit = periods.isEmpty
      ? StreakUnit.days
      : periods.last.unit;
  return HabitStats(
    currentStreak: Streak(current, unit),
    bestStreak: Streak(best, unit),
    completionRate: total == 0 ? 0 : count / total,
    completedPeriods: count,
    totalPeriods: total,
  );
}

Streak computeStreak({
  required Schedule schedule,
  required Set<String> doneDays,
  required DateTime today,
  DateTime? createdAt,
  HabitTaskType taskType = HabitTaskType.normal,
  bool twoDayRule = false,
}) {
  final stats = calculateHabitStats(
    schedule: schedule,
    doneDays: doneDays,
    createdAt: createdAt ?? addDays(today, -3650),
    today: today,
    taskType: taskType,
    twoDayRule: twoDayRule,
  );
  return stats.currentStreak;
}
