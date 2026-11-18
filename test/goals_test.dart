import 'package:ember/core/goals.dart';
import 'package:ember/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const schedule = Schedule();

  // 30 minutes until the end of January, then 60 from 1 February.
  final timeline = GoalTimeline([
    const GoalVersion(from: '2026-02-01', target: 3600, schedule: schedule),
    const GoalVersion(from: '2026-01-01', target: 1800, schedule: schedule),
  ]);

  test('each day uses the goal in force on that day', () {
    expect(timeline.targetOn(DateTime(2026, 1, 15)), 1800);
    expect(timeline.targetOn(DateTime(2026, 1, 31)), 1800);
    expect(timeline.targetOn(DateTime(2026, 2, 1)), 3600);
    expect(timeline.targetOn(DateTime(2026, 6, 1)), 3600);
  });

  test('days before the first change use the first goal', () {
    expect(timeline.targetOn(DateTime(2025, 12, 1)), 1800);
  });

  test('a single goal applies to every day', () {
    final single = GoalTimeline.single(target: 8, schedule: schedule);
    expect(single.targetOn(DateTime(1999, 1, 1)), 8);
    expect(single.targetOn(DateTime(2040, 1, 1)), 8);
  });

  test('latest is the most recent change whatever the input order', () {
    expect(timeline.latest.target, 3600);
    expect(timeline.versions.first.from, '2026-01-01');
  });

  test('old days stay done after the goal is raised', () {
    final amounts = {'2026-01-10': 1800, '2026-02-02': 1800, '2026-02-03': 3600};
    expect(timeline.doneDays(amounts), {'2026-01-10', '2026-02-03'});
    final progress = timeline.progressByDay(amounts);
    expect(progress['2026-01-10'], 1.0);
    expect(progress['2026-02-02'], closeTo(0.5, 1e-9));
    expect(progress['2026-02-03'], 1.0);
  });

  test('the streak survives a goal change', () {
    final amounts = {
      for (var d = 29; d <= 31; d++) '2026-01-$d': 1800,
      '2026-02-01': 3600,
      '2026-02-02': 3600,
    };
    final stats = calculateHabitStats(
      schedule: schedule,
      doneDays: timeline.doneDays(amounts),
      createdAt: DateTime(2026, 1, 29),
      today: DateTime(2026, 2, 2),
      dayProgress: timeline.progressByDay(amounts),
    );
    expect(stats.currentStreak.length, 5);
    expect(stats.completionRate, 1.0);
  });

  test('judging old days by the new goal would break the streak', () {
    // What used to happen: the 60 minute goal applied to every day.
    final amounts = {for (var d = 29; d <= 31; d++) '2026-01-$d': 1800, '2026-02-01': 3600};
    final strict = {for (final e in amounts.entries) if (e.value >= 3600) e.key};
    final stats = calculateHabitStats(
      schedule: schedule,
      doneDays: strict,
      createdAt: DateTime(2026, 1, 29),
      today: DateTime(2026, 2, 1),
    );
    expect(stats.currentStreak.length, 1);
  });

  test('parseDayKey round-trips', () {
    expect(parseDayKey('2026-02-01'), DateTime(2026, 2, 1));
  });
}
