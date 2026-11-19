/// What a habit can be filled in from automatically. The logic here is plain
/// Dart so it can be tested; reading Health Connect itself is in lib/health.
library;

import 'day.dart';
import 'streak.dart';

enum HealthMetric {
  none,
  steps,
  exercise,
  sleep;

  /// Stored in the database by index.
  static HealthMetric fromIndex(int index) =>
      index >= 0 && index < values.length ? values[index] : HealthMetric.none;

  String get label => switch (this) {
        HealthMetric.none => 'Manual',
        HealthMetric.steps => 'Steps',
        HealthMetric.exercise => 'Workout time',
        HealthMetric.sleep => 'Sleep',
      };

  /// Steps are counted; workout and sleep are durations.
  HabitTaskType get taskType =>
      this == HealthMetric.steps ? HabitTaskType.normal : HabitTaskType.timed;

  /// Wording for the goal field.
  String get goalLabel => switch (this) {
        HealthMetric.none => '',
        HealthMetric.steps => 'Daily step goal',
        HealthMetric.exercise => 'Daily workout goal',
        HealthMetric.sleep => 'Nightly sleep goal',
      };

  String get goalUnit => this == HealthMetric.steps ? 'steps' : 'minutes';
}

/// A stretch of time recorded by a health app (a workout, a sleep session).
class HealthSample {
  const HealthSample(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

/// Seconds of workout on [day]. A workout that runs past midnight counts for
/// each day only for the part that falls on it.
int exerciseSecondsOnDay(Iterable<HealthSample> samples, DateTime day) {
  final from = startOfDay(day);
  final to = addDays(from, 1);
  var total = 0;
  for (final s in samples) {
    final start = s.start.isBefore(from) ? from : s.start;
    final end = s.end.isAfter(to) ? to : s.end;
    if (end.isAfter(start)) total += end.difference(start).inSeconds;
  }
  return total;
}

/// Seconds of sleep for [day]. A night counts for the day you wake up on, so
/// last night's sleep belongs to today.
int sleepSecondsForDay(Iterable<HealthSample> samples, DateTime day) {
  final from = startOfDay(day);
  final to = addDays(from, 1);
  var total = 0;
  for (final s in samples) {
    if (!s.end.isBefore(from) && s.end.isBefore(to) && s.end.isAfter(s.start)) {
      total += s.end.difference(s.start).inSeconds;
    }
  }
  return total;
}

/// The window of samples worth fetching for [day]: from the evening before
/// (so a night that started yesterday is included) to the end of the day.
({DateTime from, DateTime to}) fetchWindowFor(DateTime day) =>
    (from: addDays(startOfDay(day), -1), to: addDays(startOfDay(day), 1));

/// Whether a value read from a health app should replace what is logged.
/// Never lowers a day: a manual entry above the health value is kept.
bool shouldRaise({required int logged, required int fromHealth}) => fromHealth > logged;
