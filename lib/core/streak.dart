import 'day.dart';

enum ScheduleType { daily, weekdays, timesPerWeek }

enum StreakUnit { days, weeks }

const weekdayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// When a habit is expected to be done.
class Schedule {
  const Schedule({
    this.type = ScheduleType.daily,
    this.weekdayMask = allDaysMask,
    this.timesPerWeek = 7,
  });

  /// Bit 0 = Monday ... bit 6 = Sunday.
  static const allDaysMask = 127;

  final ScheduleType type;
  final int weekdayMask;
  final int timesPerWeek;

  /// Whether a missed [day] would break the streak.
  bool isDue(DateTime day) {
    switch (type) {
      case ScheduleType.daily:
      case ScheduleType.timesPerWeek:
        return true;
      case ScheduleType.weekdays:
        return ((weekdayMask >> (day.weekday - 1)) & 1) == 1;
    }
  }

  String describe() {
    switch (type) {
      case ScheduleType.daily:
        return 'Every day';
      case ScheduleType.timesPerWeek:
        return '$timesPerWeek times a week';
      case ScheduleType.weekdays:
        {
          final days = [
            for (var i = 0; i < 7; i++)
              if (((weekdayMask >> i) & 1) == 1) weekdayShortNames[i],
          ];
          return days.isEmpty ? 'No days selected' : days.join(', ');
        }
    }
  }
}

class Streak {
  const Streak(this.length, this.unit);

  final int length;
  final StreakUnit unit;

  String get shortLabel => '$length${unit == StreakUnit.days ? 'd' : 'w'}';

  String get longLabel {
    final noun = unit == StreakUnit.days ? 'day' : 'week';
    return '$length $noun${length == 1 ? '' : 's'}';
  }
}

/// Current streak for a habit.
///
/// [doneDays] holds the day keys on which the habit's daily target was met.
/// Today never breaks a streak while it is still open.
Streak computeStreak({
  required Schedule schedule,
  required Set<String> doneDays,
  required DateTime today,
}) {
  final t = startOfDay(today);
  return schedule.type == ScheduleType.timesPerWeek
      ? _weeklyStreak(schedule, doneDays, t)
      : _dailyStreak(schedule, doneDays, t);
}

Streak _dailyStreak(Schedule schedule, Set<String> doneDays, DateTime today) {
  var length = 0;
  var cursor = today;
  // Scan back at most ten years.
  for (var i = 0; i < 3660; i++) {
    if (doneDays.contains(dayKey(cursor))) {
      length++;
    } else if (schedule.isDue(cursor) && cursor != today) {
      break;
    }
    cursor = addDays(cursor, -1);
  }
  return Streak(length, StreakUnit.days);
}

Streak _weeklyStreak(Schedule schedule, Set<String> doneDays, DateTime today) {
  final thisWeek = startOfWeek(today);
  var length = 0;
  var weekStart = thisWeek;
  // Scan back at most ten years.
  for (var i = 0; i < 520; i++) {
    var done = 0;
    for (var d = 0; d < 7; d++) {
      if (doneDays.contains(dayKey(addDays(weekStart, d)))) done++;
    }
    if (done >= schedule.timesPerWeek) {
      length++;
    } else if (weekStart != thisWeek) {
      break;
    }
    weekStart = addDays(weekStart, -7);
  }
  return Streak(length, StreakUnit.weeks);
}
