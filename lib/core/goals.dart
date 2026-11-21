/// A habit's goal can change over time (30 minutes, then 60). Each change is
/// recorded with the day it takes effect, so past days are always judged
/// against the goal that applied then.
library;

import 'day.dart';
import 'streak.dart';

/// The goal in force from [from] (a `yyyy-MM-dd` day key) until the next change.
class GoalVersion {
  const GoalVersion({required this.from, required this.target, required this.schedule});
  final String from;

  /// What counts as done on a day: taps for a normal habit, seconds for a timed one.
  final int target;
  final Schedule schedule;
}

class GoalTimeline {
  /// [versions] may be in any order. Must not be empty.
  GoalTimeline(List<GoalVersion> versions)
      : assert(versions.isNotEmpty),
        _versions = ([...versions]..sort((a, b) => a.from.compareTo(b.from)));

  /// A habit whose goal never changed.
  GoalTimeline.single({required int target, required Schedule schedule})
      : _versions = [GoalVersion(from: '0000-01-01', target: target, schedule: schedule)];

  final List<GoalVersion> _versions;

  List<GoalVersion> get versions => List.unmodifiable(_versions);

  /// The goal that applied on [day]. Days before the first change use the first goal.
  GoalVersion at(DateTime day) {
    final key = dayKey(day);
    var found = _versions.first;
    for (final v in _versions) {
      if (v.from.compareTo(key) <= 0) found = v;
    }
    return found;
  }

  int targetOn(DateTime day) => at(day).target;
  Schedule scheduleOn(DateTime day) => at(day).schedule;

  /// The goal now (the last change).
  GoalVersion get latest => _versions.last;

  /// The share (0 to 1) of each logged day's own goal that was reached.
  Map<String, double> progressByDay(Map<String, int> amounts) => {
        for (final e in amounts.entries)
          e.key: _share(e.value, targetOn(parseDayKey(e.key))),
      };

  /// Days whose logged amount reached that day's own goal.
  Set<String> doneDays(Map<String, int> amounts) => {
        for (final e in amounts.entries)
          if (e.value >= targetOn(parseDayKey(e.key))) e.key,
      };

  /// For a limit habit ("stay under 30 minutes"): every day from [from]
  /// through [through] whose logged amount stayed within that day's own limit.
  /// A day with nothing logged is a success, so the days are counted even
  /// though they have no row.
  Set<String> underLimitDays(Map<String, int> amounts, DateTime from, DateTime through) {
    final days = <String>{};
    var day = startOfDay(from);
    final last = startOfDay(through);
    for (var i = 0; !day.isAfter(last) && i < 4000; i++, day = addDays(day, 1)) {
      final key = dayKey(day);
      if ((amounts[key] ?? 0) <= targetOn(day)) days.add(key);
    }
    return days;
  }

  static double _share(int amount, int target) =>
      target <= 0 ? 0.0 : (amount / target).clamp(0.0, 1.0).toDouble();
}

/// Turns a `yyyy-MM-dd` key back into a date.
DateTime parseDayKey(String key) =>
    DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(5, 7)), int.parse(key.substring(8, 10)));
