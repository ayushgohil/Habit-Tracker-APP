import 'package:ember/core/day.dart';
import 'package:ember/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> keys(Iterable<DateTime> days) => days.map(dayKey).toSet();

void main() {
  final monday = DateTime(2026, 11, 16);

  group('daily schedules', () {
    test('counts consecutive days and leaves the current day open', () {
      final result = computeStreak(
        schedule: const Schedule(),
        doneDays: keys([addDays(monday, -1), addDays(monday, -2)]),
        today: monday,
      );
      expect(result.length, 2);
      expect(result.unit, StreakUnit.days);
    });

    test('a missed due day breaks a normal streak', () {
      final result = computeStreak(
        schedule: const Schedule(),
        doneDays: keys([monday, addDays(monday, -2)]),
        today: monday,
      );
      expect(result.length, 1);
    });

    test('weekday schedule ignores unselected days', () {
      const schedule = Schedule(type: ScheduleType.weekdays, weekdayMask: 21);
      final wednesday = addDays(monday, 2);
      final result = computeStreak(
        schedule: schedule,
        doneDays: keys([wednesday, monday, addDays(monday, -3)]),
        today: wednesday,
      );
      expect(result.length, 3);
    });

    test('every N days uses habit creation as its anchor', () {
      final result = computeStreak(
        schedule: Schedule(
          type: ScheduleType.everyNDays,
          intervalDays: 3,
          anchorDate: monday,
        ),
        doneDays: keys([monday, addDays(monday, 3), addDays(monday, 6)]),
        today: addDays(monday, 6),
      );
      expect(result.length, 3);
    });
  });

  test('weekday completion rate ignores unscheduled days', () {
    const schedule = Schedule(type: ScheduleType.weekdays, weekdayMask: 21);
    final stats = calculateHabitStats(
      schedule: schedule,
      doneDays: keys([monday, addDays(monday, 2)]),
      createdAt: monday,
      today: addDays(monday, 6),
    );
    expect(stats.totalPeriods, 2);
    expect(stats.completedPeriods, 2);
    expect(stats.completionRate, 1);
  });

  group('weekly schedules', () {
    test('N times per week counts completed weeks', () {
      const schedule = Schedule(
        type: ScheduleType.timesPerWeek,
        timesPerWeek: 3,
      );
      final last = addDays(monday, -7);
      final before = addDays(monday, -14);
      final result = computeStreak(
        schedule: schedule,
        doneDays: keys([
          monday,
          last,
          addDays(last, 2),
          addDays(last, 4),
          before,
          addDays(before, 1),
          addDays(before, 3),
        ]),
        today: monday,
      );
      expect(result.length, 2);
      expect(result.unit, StreakUnit.weeks);
    });

    test('weekly goal counts a completed week', () {
      final week = addDays(monday, -7);
      final result = computeStreak(
        schedule: const Schedule(type: ScheduleType.weekly),
        doneDays: keys([week]),
        today: monday,
      );
      expect(result.length, 1);
    });

    test('fortnightly goal uses consecutive two-week periods', () {
      final previous = addDays(monday, -14);
      final result = computeStreak(
        schedule: const Schedule(type: ScheduleType.fortnightly),
        doneDays: keys([previous]),
        today: monday,
      );
      expect(result.length, 1);
      expect(result.unit, StreakUnit.fortnights);
    });
  });

  group('calendar schedules', () {
    test('monthly goals use calendar months', () {
      final previousMonth = DateTime(2026, 10, 10);
      final result = computeStreak(
        schedule: const Schedule(type: ScheduleType.monthly),
        doneDays: keys([previousMonth]),
        today: monday,
      );
      expect(result.length, 1);
      expect(result.unit, StreakUnit.months);
    });

    test('yearly goals use calendar years', () {
      final previousYear = DateTime(2025, 6, 10);
      final result = computeStreak(
        schedule: const Schedule(type: ScheduleType.yearly),
        doneDays: keys([previousYear]),
        today: monday,
      );
      expect(result.length, 1);
      expect(result.unit, StreakUnit.years);
    });
  });

  group('negative habits', () {
    const daily = Schedule();
    test('2-day rule tolerates one missed day', () {
      final result = computeStreak(
        schedule: daily,
        doneDays: keys([monday, addDays(monday, -2)]),
        today: monday,
        taskType: HabitTaskType.negative,
        twoDayRule: true,
      );
      expect(result.length, 2);
    });

    test('2 consecutive misses break the streak', () {
      final result = computeStreak(
        schedule: daily,
        doneDays: keys([monday, addDays(monday, -3)]),
        today: monday,
        taskType: HabitTaskType.negative,
        twoDayRule: true,
      );
      expect(result.length, 1);
    });
  });

  group('habit statistics', () {
    test('calculates best streak and completion rate', () {
      final stats = calculateHabitStats(
        schedule: const Schedule(),
        doneDays: keys([
          monday,
          addDays(monday, -1),
          addDays(monday, -3),
          addDays(monday, -4),
        ]),
        createdAt: addDays(monday, -4),
        today: monday,
      );
      expect(stats.bestStreak.length, 2);
      expect(stats.completedPeriods, 4);
      expect(stats.totalPeriods, 5);
      expect(stats.completionRate, 0.8);
    });
  });

  test('schedule descriptions cover every type', () {
    expect(const Schedule().describe(), 'Every day');
    expect(
      const Schedule(type: ScheduleType.weekly).describe(),
      'Weekly',
    );
    expect(
      const Schedule(type: ScheduleType.fortnightly).describe(),
      'Every 2 weeks',
    );
    expect(
      const Schedule(type: ScheduleType.monthly).describe(),
      'Monthly',
    );
    expect(
      const Schedule(type: ScheduleType.yearly).describe(),
      'Yearly',
    );
    expect(
      const Schedule(type: ScheduleType.everyNDays, intervalDays: 4).describe(),
      'Every 4 days',
    );
  });
}
