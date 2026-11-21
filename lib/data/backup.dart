import 'dart:convert';

import '../core/goals.dart';
import '../core/streak.dart';
import 'database.dart';
import 'providers.dart';

/// Thrown when a backup file can't be read or isn't an Ember backup.
class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a restore brought in.
class RestoreSummary {
  const RestoreSummary({required this.habits, required this.days});
  final int habits;
  final int days;
}

const backupFormatVersion = 1;

/// Everything Ember stores, as one JSON document.
Future<String> exportBackupJson(AppDatabase db, {DateTime? now}) async {
  final data = <String, Object?>{
    'app': 'ember',
    'version': backupFormatVersion,
    'exportedAt': (now ?? DateTime.now()).toIso8601String(),
    'habits': [for (final r in await db.select(db.habits).get()) r.toJson()],
    'completions': [for (final r in await db.select(db.completions).get()) r.toJson()],
    'dayNotes': [for (final r in await db.select(db.dayNotes).get()) r.toJson()],
    'habitGoals': [for (final r in await db.select(db.habitGoals).get()) r.toJson()],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// Replaces all data with the contents of a backup made by [exportBackupJson].
/// Nothing is changed if the file is invalid.
Future<RestoreSummary> restoreBackupJson(AppDatabase db, String source) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw BackupException('This file is not a valid backup.');
  }
  if (decoded is! Map<String, dynamic> || decoded['app'] != 'ember') {
    throw BackupException('This is not an Ember backup file.');
  }
  final Map<String, dynamic> root = decoded;
  final version = root['version'];
  if (version is! int || version < 1 || version > backupFormatVersion) {
    throw BackupException('This backup was made by a newer version of Ember. Update the app and try again.');
  }

  List<T> rows<T>(String key, T Function(Map<String, dynamic>) parse) {
    final list = root[key];
    if (list == null) return <T>[];
    if (list is! List) throw BackupException('The backup is damaged ($key).');
    return [
      for (final item in list)
        if (item is Map<String, dynamic>) parse(item) else throw BackupException('The backup is damaged ($key).'),
    ];
  }

  final List<Habit> habitRows;
  final List<Completion> completionRows;
  final List<DayNote> noteRows;
  final List<HabitGoal> goalRows;
  try {
    // Backups made before a column existed don't have it; use its default.
    habitRows = rows('habits', (m) => Habit.fromJson({'healthMetric': 0, 'unitLabel': '', 'stepSize': 1, 'extraReminders': '', 'sessionSeconds': 0, ...m}));
    completionRows = rows('completions', Completion.fromJson);
    noteRows = rows('dayNotes', (m) => DayNote.fromJson({'pinned': false, ...m}));
    goalRows = rows('habitGoals', HabitGoal.fromJson);
  } on BackupException {
    rethrow;
  } catch (_) {
    throw BackupException('The backup is damaged or incomplete.');
  }
  final known = {for (final h in habitRows) h.id};
  if (known.length != habitRows.length ||
      completionRows.any((c) => !known.contains(c.habitId)) ||
      goalRows.any((g) => !known.contains(g.habitId))) {
    throw BackupException('The backup is damaged (habits do not match their history).');
  }

  await db.replaceAllData(
    habitRows: habitRows,
    completionRows: completionRows,
    noteRows: noteRows,
    goalRows: goalRows,
  );
  return RestoreSummary(habits: habitRows.length, days: completionRows.length);
}

String _csv(String value) =>
    value.contains(RegExp('[",\n\r]')) ? '"${value.replaceAll('"', '""')}"' : value;

/// One row per logged day: habit, date, amount, that day's goal and whether it was met.
Future<String> exportHistoryCsv(AppDatabase db) async {
  final habits = await db.select(db.habits).get();
  final goals = await db.select(db.habitGoals).get();
  final completions = await db.select(db.completions).get();
  final timelines = {for (final h in habits) h.id: timelineFor(h, goals)};
  final byId = {for (final h in habits) h.id: h};
  final sorted = [...completions]..sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.habitId.compareTo(b.habitId);
    });
  final out = StringBuffer('habit,date,amount,unit,goal,done\n');
  for (final c in sorted) {
    final habit = byId[c.habitId];
    if (habit == null) continue;
    final goal = timelines[habit.id]!.targetOn(parseDayKey(c.day));
    final timed = habit.taskType == HabitTaskType.timed.index;
    out.writeln([
      _csv(habit.name),
      c.day,
      c.amount,
      timed ? 'seconds' : 'times',
      goal,
      c.amount >= goal ? 'yes' : 'no',
    ].join(','));
  }
  return out.toString();
}
