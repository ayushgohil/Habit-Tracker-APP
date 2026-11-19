import 'package:ember/core/health.dart';
import 'package:ember/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 11, 19);
  HealthSample s(DateTime a, DateTime b) => HealthSample(a, b);

  group('exerciseSecondsOnDay', () {
    test('adds up the workouts on the day', () {
      final seconds = exerciseSecondsOnDay([
        s(DateTime(2026, 11, 19, 7), DateTime(2026, 11, 19, 7, 30)),
        s(DateTime(2026, 11, 19, 18), DateTime(2026, 11, 19, 18, 45)),
      ], day);
      expect(seconds, 75 * 60);
    });

    test('a workout across midnight is split between the two days', () {
      final late = s(DateTime(2026, 11, 18, 23, 30), DateTime(2026, 11, 19, 0, 30));
      expect(exerciseSecondsOnDay([late], day), 30 * 60);
      expect(exerciseSecondsOnDay([late], DateTime(2026, 11, 18)), 30 * 60);
    });

    test('other days and empty or backwards samples count for nothing', () {
      expect(exerciseSecondsOnDay([s(DateTime(2026, 11, 20, 7), DateTime(2026, 11, 20, 8))], day), 0);
      expect(exerciseSecondsOnDay([s(DateTime(2026, 11, 19, 9), DateTime(2026, 11, 19, 8))], day), 0);
      expect(exerciseSecondsOnDay(const [], day), 0);
    });
  });

  group('sleepSecondsForDay', () {
    test('a night counts for the day you wake up', () {
      final night = s(DateTime(2026, 11, 18, 23), DateTime(2026, 11, 19, 6, 30));
      expect(sleepSecondsForDay([night], day), 7.5 * 3600);
      expect(sleepSecondsForDay([night], DateTime(2026, 11, 18)), 0);
    });

    test('a nap and a night add up', () {
      final seconds = sleepSecondsForDay([
        s(DateTime(2026, 11, 18, 23, 30), DateTime(2026, 11, 19, 6)),
        s(DateTime(2026, 11, 19, 14), DateTime(2026, 11, 19, 14, 30)),
      ], day);
      expect(seconds, 6.5 * 3600 + 30 * 60);
    });
  });

  test('fetch window starts the evening before and ends after the day', () {
    final w = fetchWindowFor(DateTime(2026, 11, 19, 15, 20));
    expect(w.from, DateTime(2026, 11, 18));
    expect(w.to, DateTime(2026, 11, 20));
  });

  test('health values only ever raise a logged day', () {
    expect(shouldRaise(logged: 0, fromHealth: 4000), isTrue);
    expect(shouldRaise(logged: 4000, fromHealth: 4000), isFalse);
    expect(shouldRaise(logged: 9000, fromHealth: 4000), isFalse);
  });

  test('metrics map to the right habit type and survive bad indexes', () {
    expect(HealthMetric.steps.taskType, HabitTaskType.normal);
    expect(HealthMetric.exercise.taskType, HabitTaskType.timed);
    expect(HealthMetric.sleep.taskType, HabitTaskType.timed);
    expect(HealthMetric.fromIndex(2), HealthMetric.exercise);
    expect(HealthMetric.fromIndex(99), HealthMetric.none);
    expect(HealthMetric.fromIndex(-1), HealthMetric.none);
  });
}
