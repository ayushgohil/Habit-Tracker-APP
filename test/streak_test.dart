import 'package:ember/core/day.dart';
import 'package:ember/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> keys(List<DateTime> days) => days.map(dayKey).toSet();

void main() {
  // Monday 16 November 2026.
  final monday = DateTime(2026, 11, 16);

  group('daily habits', () {
    const schedule = Schedule();

    test('counts consecutive days ending today', () {
      final done = keys([monday, addDays(monday, -1), addDays(monday, -2)]);
      final streak =
          computeStreak(schedule: schedule, doneDays: done, today: monday);
      expect(streak.length, 3);
      expect(streak.unit, StreakUnit.days);
    });

    test('an unfinished today does not break the streak', () {
      final done = keys([addDays(monday, -1), addDays(monday, -2)]);
      final streak =
          computeStreak(schedule: schedule, doneDays: done, today: monday);
      expect(streak.length, 2);
    });

    test('a missed day ends the streak', () {
      final done = keys([monday, addDays(monday, -2)]);
      final streak =
          computeStreak(schedule: schedule, doneDays: done, today: monday);
      expect(streak.length, 1);
    });

    test('no completions means no streak', () {
      final streak =
          computeStreak(schedule: schedule, doneDays: {}, today: monday);
      expect(streak.length, 0);
    });
  });

  group('specific weekdays', () {
    // Monday, Wednesday, Friday.
    const schedule = Schedule(type: ScheduleType.weekdays, weekdayMask: 21);

    test('skips days that are not scheduled', () {
      final wednesday = addDays(monday, 2);
      final done = keys([
        wednesday,
        monday,
        addDays(monday, -3), // previous Friday
      ]);
      final streak =
          computeStreak(schedule: schedule, doneDays: done, today: wednesday);
      expect(streak.length, 3);
    });

    test('missing a scheduled day ends the streak', () {
      final wednesday = addDays(monday, 2);
      final done = keys([wednesday, addDays(monday, -3)]); // Monday missed
      final streak =
          computeStreak(schedule: schedule, doneDays: done, today: wednesday);
      expect(streak.length, 1);
    });
  });

  group('times per week', () {
    const schedule = Schedule(type: ScheduleType.timesPerWeek, timesPerWeek: 3);

    test('counts whole weeks that met the target', () {
      final lastWeek = addDays(monday, -7);
      final weekBefore = addDays(monday, -14);
      final done = keys([
        monday, // this week: 1 of 3, still open
        lastWeek,
        addDays(lastWeek, 2),
        addDays(lastWeek, 4),
        weekBefore,
        addDays(weekBefore, 1),
        addDays(weekBefore, 3),
      ]);
      final streak =
          computeStreak(schedule: schedule, doneDays: done, today: monday);
      expect(streak.length, 2);
      expect(streak.unit, StreakUnit.weeks);
    });

    test('a short week ends the streak', () {
      final lastWeek = addDays(monday, -7);
      final done = keys([lastWeek, addDays(lastWeek, 1)]); // only 2 of 3
      final streak =
          computeStreak(schedule: schedule, doneDays: done, today: monday);
      expect(streak.length, 0);
    });
  });

  group('day helpers', () {
    test('dayKey pads month and day', () {
      expect(dayKey(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('startOfWeek is the Monday', () {
      expect(startOfWeek(DateTime(2026, 11, 20)), DateTime(2026, 11, 16));
    });
  });
}
