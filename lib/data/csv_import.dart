import '../core/day.dart';
import '../core/goals.dart' show parseDayKey;
import 'database.dart';

class CsvImportResult {
  const CsvImportResult({required this.imported, required this.habits, required this.skipped, required this.unknownHabits});

  /// Days written (new, or raised above what was already logged).
  final int imported;

  /// How many different habits those days belong to.
  final int habits;

  /// Rows left out: bad dates or amounts, future days, days before a habit's
  /// start, values that would lower what is already logged, unknown habits.
  final int skipped;
  final Set<String> unknownHabits;
}

class CsvImportException implements Exception {
  const CsvImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Splits CSV text into rows of fields (quotes, escaped quotes and line breaks
/// inside quotes are handled).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var any = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
    any = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    if (c == '"') {
      quoted = true;
      any = true;
    } else if (c == ',') {
      endField();
      any = true;
    } else if (c == '\n') {
      endRow();
    } else if (c == '\r') {
      // Handled with the following \n (or ignored).
    } else {
      field.write(c);
      any = true;
    }
  }
  if (any || field.isNotEmpty) endRow();
  return rows;
}

/// Brings logged days in from a CSV in Ember's own export format
/// (`habit,date,amount,...`). Habits are matched by name; habits that do not
/// exist are not created. Nothing already logged is ever lowered.
Future<CsvImportResult> importHistoryCsv(AppDatabase db, String csv, {DateTime? today}) async {
  final rows = parseCsv(csv.replaceFirst('﻿', ''));
  if (rows.isEmpty) throw const CsvImportException('That file is empty.');
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  final nameAt = header.indexOf('habit');
  final dateAt = header.indexOf('date');
  final amountAt = header.indexOf('amount');
  if (nameAt < 0 || dateAt < 0 || amountAt < 0) {
    throw const CsvImportException('This does not look like an Ember history file. It needs habit, date and amount columns.');
  }

  final last = today ?? currentDay();
  final habits = await db.select(db.habits).get();
  final byName = <String, Habit>{};
  for (final h in habits) {
    byName.putIfAbsent(h.name.trim().toLowerCase(), () => h);
  }

  var imported = 0;
  var skipped = 0;
  final touched = <int>{};
  final unknown = <String>{};

  await db.transaction(() async {
    for (final row in rows.skip(1)) {
      String at(int i) => i < row.length ? row[i].trim() : '';
      final name = at(nameAt);
      final habit = byName[name.toLowerCase()];
      if (habit == null) {
        if (name.isNotEmpty) unknown.add(name);
        skipped++;
        continue;
      }
      final date = at(dateAt);
      final amount = int.tryParse(at(amountAt));
      final DateTime day;
      try {
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) throw const FormatException();
        day = parseDayKey(date);
        if (dayKey(day) != date) throw const FormatException();
      } on FormatException {
        skipped++;
        continue;
      }
      if (amount == null || amount <= 0 || amount > 10000000 || day.isAfter(last) || day.isBefore(startOfDay(habit.createdAt))) {
        skipped++;
        continue;
      }
      if (await db.loggedAmount(habit.id, date) >= amount) {
        skipped++;
        continue;
      }
      await db.setCompletion(habitId: habit.id, day: date, amount: amount);
      imported++;
      touched.add(habit.id);
    }
  });
  return CsvImportResult(imported: imported, habits: touched.length, skipped: skipped, unknownHabits: unknown);
}
