import 'package:ember/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 18);

  HabitStats stats({
    Schedule schedule = const Schedule(),
    Map<String, double>? progress,
    Set<String> done = const {},
    DateTime? created,
  }) =>
      calculateHabitStats(
        schedule: schedule,
        doneDays: done,
        createdAt: created ?? today,
        today: today,
        dayProgress: progress,
      );

  test('partly done today counts towards completion, not towards streaks', () {
    // 6 of 30 minutes.
    final s = stats(progress: {'2026-11-18': 0.2});
    expect(s.completionRate, closeTo(0.2, 1e-9));
    expect(s.completedPeriods, 0);
    expect(s.currentStreak.length, 0);
  });

  test('without progress the rate only counts fully done periods', () {
    expect(stats().completionRate, 0);
    expect(stats(done: {'2026-11-18'}).completionRate, 1);
  });

  test('fully done days and partial days are averaged over the period count', () {
    final s = stats(
      created: DateTime(2026, 11, 16),
      done: {'2026-11-16'},
      progress: {'2026-11-16': 1.0, '2026-11-17': 0.5},
    );
    // Three days: 1 + 0.5 + 0.
    expect(s.completionRate, closeTo(0.5, 1e-9));
  });

  test('weekly habits share partial progress across the week', () {
    final s = stats(
      schedule: const Schedule(type: ScheduleType.timesPerWeek, timesPerWeek: 4),
      created: DateTime(2026, 11, 16),
      progress: {'2026-11-16': 1.0, '2026-11-17': 1.0},
    );
    expect(s.completionRate, closeTo(0.5, 1e-9));
  });
}
