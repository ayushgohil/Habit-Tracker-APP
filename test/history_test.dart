import 'package:ember/core/day.dart';
import 'package:ember/core/history.dart';
import 'package:ember/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tuesday 17 November 2026.
  final today = DateTime(2026, 11, 17);
  final start = DateTime(2026, 11, 2);

  DayState state(
    int offsetFromToday, {
    Schedule schedule = const Schedule(),
    int amount = 0,
    int target = 1,
    DateTime? habitStart,
  }) {
    return dayStateFor(
      schedule: schedule,
      amount: amount,
      target: target,
      day: addDays(today, offsetFromToday),
      today: today,
      start: habitStart ?? start,
    );
  }

  group('dayStateFor', () {
    test('days before the start are not part of the history', () {
      expect(state(-20), DayState.beforeStart);
    });

    test('days after today are in the future', () {
      expect(state(1), DayState.future);
    });

    test('a finished day is done, even on a day that was not scheduled', () {
      expect(state(-3, amount: 1), DayState.done);
      const weekdays = Schedule(type: ScheduleType.weekdays, weekdayMask: 21);
      // Tuesday is not a Mon/Wed/Fri day, but it was logged anyway.
      expect(state(0, schedule: weekdays, amount: 1), DayState.done);
    });

    test('some progress short of the target is partial', () {
      expect(state(-1, amount: 3, target: 8), DayState.partial);
    });

    test('an empty scheduled day that has passed is missed', () {
      expect(state(-1), DayState.missed);
    });

    test('today, still to do, is open rather than missed', () {
      expect(state(0), DayState.open);
    });

    test('a day the habit is not scheduled is not a miss', () {
      const weekdays = Schedule(type: ScheduleType.weekdays, weekdayMask: 21);
      // Monday 16 is scheduled and empty, Sunday 15 is not scheduled.
      expect(state(-1, schedule: weekdays), DayState.missed);
      expect(state(-2, schedule: weekdays), DayState.notScheduled);
    });

    test('habits judged over a week or longer have no missed days', () {
      const weekly = Schedule(type: ScheduleType.timesPerWeek, timesPerWeek: 3);
      expect(state(-1, schedule: weekly), DayState.none);
      expect(state(0, schedule: weekly), DayState.open);
    });

    test('a zero target is never done', () {
      expect(state(-1, amount: 5, target: 0), DayState.partial);
    });
  });

  group('monthGrid', () {
    test('November 2026 starts on a Sunday and needs six weeks', () {
      final grid = monthGrid(DateTime(2026, 11, 20));
      expect(grid, hasLength(6));
      expect(grid.every((week) => week.length == 7), isTrue);
      expect(grid.first.take(6).every((cell) => cell == null), isTrue);
      expect(grid.first.last, DateTime(2026, 11, 1));
      expect(grid.last.first, DateTime(2026, 11, 30));
      expect(grid.last.skip(1).every((cell) => cell == null), isTrue);
    });

    test('February 2027 starts on a Monday and fits four weeks', () {
      final grid = monthGrid(DateTime(2027, 2));
      expect(grid, hasLength(4));
      expect(grid.first.first, DateTime(2027, 2, 1));
      expect(grid.last.last, DateTime(2027, 2, 28));
      expect(grid.expand((week) => week).every((cell) => cell != null), isTrue);
    });

    test('every day of the month appears exactly once', () {
      final days = monthGrid(DateTime(2028, 2)) // a leap year
          .expand((week) => week)
          .whereType<DateTime>()
          .toList();
      expect(days, hasLength(29));
      expect(days.first, DateTime(2028, 2, 1));
      expect(days.last, DateTime(2028, 2, 29));
    });
  });

  group('chart series', () {
    test('dailyProgress runs oldest first and clamps to the target', () {
      final series = dailyProgress(
        amounts: {
          dayKey(today): 8,
          dayKey(addDays(today, -1)): 2,
          dayKey(addDays(today, -2)): 20, // more than the target
        },
        target: 8,
        end: today,
        days: 4,
      );
      expect(series, [0.0, 1.0, 0.25, 1.0]);
    });

    test('dailyProgress is all zeros for a zero target', () {
      final series = dailyProgress(
        amounts: {dayKey(today): 3},
        target: 0,
        end: today,
        days: 3,
      );
      expect(series, [0.0, 0.0, 0.0]);
    });

    test('doneDaysPerMonth counts each month and crosses year ends', () {
      final counts = doneDaysPerMonth(
        doneDays: {
          '2026-11-01',
          '2026-11-02',
          '2026-11-17',
          '2026-10-30',
          '2026-01-05',
          '2025-12-31',
        },
        end: today,
        months: 12,
      );
      expect(counts, hasLength(12));
      // Oldest first: Dec 2025 ... Nov 2026.
      expect(counts.first, 1); // Dec 2025
      expect(counts[1], 1); // Jan 2026
      expect(counts[10], 1); // Oct 2026
      expect(counts.last, 3); // Nov 2026
      expect(counts.fold<int>(0, (a, b) => a + b), 6);
    });

    test('doneDaysInMonth only counts the month of the day', () {
      final done = {'2026-11-01', '2026-11-17', '2026-10-31'};
      expect(doneDaysInMonth(done, today), 2);
      expect(doneDaysInMonth(done, DateTime(2026, 10, 5)), 1);
    });
  });
}
