import 'package:ember/core/day.dart';
import 'package:ember/core/habit_order.dart';
import 'package:ember/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> keys(Iterable<DateTime> days) => days.map(dayKey).toSet();

void main() {
  // Monday 16 November 2026.
  final monday = DateTime(2026, 11, 16);

  group('specific weekdays: a scheduled day that has passed is over', () {
    // Monday, Wednesday, Friday.
    const schedule = Schedule(type: ScheduleType.weekdays, weekdayMask: 21);
    final tuesday = addDays(monday, 1);

    test('missing Monday breaks the streak on Tuesday', () {
      final result = computeStreak(
        schedule: schedule,
        doneDays: keys([
          addDays(monday, -3), // Friday
          addDays(monday, -5), // Wednesday
        ]),
        today: tuesday,
      );
      expect(result.length, 0);
    });

    test('doing Monday keeps the streak alive on Tuesday', () {
      final result = computeStreak(
        schedule: schedule,
        doneDays: keys([
          monday,
          addDays(monday, -3),
          addDays(monday, -5),
        ]),
        today: tuesday,
      );
      expect(result.length, 3);
    });

    test('a scheduled day that is still today stays open', () {
      final result = computeStreak(
        schedule: schedule,
        doneDays: keys([addDays(monday, -3), addDays(monday, -5)]),
        today: monday,
      );
      expect(result.length, 2);
    });
  });

  group('every N days: any day inside the window counts', () {
    final schedule = Schedule(
      type: ScheduleType.everyNDays,
      intervalDays: 3,
      anchorDate: monday,
    );

    test('doing it early in the window still completes the window', () {
      final result = computeStreak(
        schedule: schedule,
        // Window 1 is days 0-2, done on day 1. Window 2 is days 3-5, done on
        // day 3.
        doneDays: keys([addDays(monday, 1), addDays(monday, 3)]),
        today: addDays(monday, 4),
        createdAt: monday,
      );
      expect(result.length, 2);
    });

    test('an empty window still breaks the streak', () {
      final result = computeStreak(
        schedule: schedule,
        doneDays: keys([addDays(monday, 3)]),
        today: addDays(monday, 4),
        createdAt: monday,
      );
      expect(result.length, 1);
    });
  });

  group('daysBetween', () {
    test('counts whole calendar days', () {
      expect(daysBetween(DateTime(1970, 1, 5), DateTime(2026, 11, 16)), 20769);
    });

    test('ignores time of day', () {
      expect(
        daysBetween(DateTime(2026, 3, 8, 23, 59), DateTime(2026, 3, 9, 0, 1)),
        1,
      );
    });

    test('is negative when the second date is earlier', () {
      expect(daysBetween(DateTime(2026, 11, 17), DateTime(2026, 11, 16)), -1);
    });
  });

  group('reorderWithinGroup', () {
    test('moves a pending habit without touching the others', () {
      // Saved order 1,2,3,4. Habits 2 and 4 are pending, and 4 is dragged
      // above 2. Habits 1 and 3 keep their slots.
      final result = reorderWithinGroup(
        persisted: [1, 2, 3, 4],
        displayedAfterMove: [4, 2, 1, 3],
        group: {2, 4},
      );
      expect(result, [1, 4, 3, 2]);
    });

    test('moves a finished habit without touching the pending ones', () {
      final result = reorderWithinGroup(
        persisted: [1, 2, 3, 4],
        displayedAfterMove: [2, 4, 3, 1],
        group: {1, 3},
      );
      expect(result, [3, 2, 1, 4]);
    });

    test('a drag that changes nothing leaves the saved order alone', () {
      final result = reorderWithinGroup(
        persisted: [1, 2, 3, 4],
        displayedAfterMove: [2, 4, 1, 3],
        group: {2, 4},
      );
      expect(result, [1, 2, 3, 4]);
    });
  });
}
