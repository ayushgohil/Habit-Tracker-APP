import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class DayNotes extends Table {
  IntColumn get habitId => integer().references(Habits, #id, onDelete: KeyAction.cascade)();
  TextColumn get day => text().withLength(min: 10, max: 10)();
  TextColumn get note => text()();
  @override
  Set<Column> get primaryKey => {habitId, day};
}


class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// Key into `habitIcons`.
  TextColumn get iconKey => text()();

  /// ARGB colour value.
  IntColumn get colorValue => integer()();

  /// Index into `ScheduleType` (0 daily, 1 weekdays, 2 times per week).
  IntColumn get scheduleType => integer().withDefault(const Constant(0))();

  /// Bit 0 = Monday ... bit 6 = Sunday. Used when scheduleType is weekdays.
  IntColumn get weekdayMask => integer().withDefault(const Constant(127))();

  /// Used when scheduleType is times per week.
  IntColumn get timesPerWeek => integer().withDefault(const Constant(7))();

  /// How many taps complete a day (e.g. 8 glasses of water).
  IntColumn get dailyTarget => integer().withDefault(const Constant(1))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  IntColumn get taskType => integer().withDefault(const Constant(0))();
  BoolColumn get twoDayRule => boolean().withDefault(const Constant(false))();
  IntColumn get intervalDays => integer().withDefault(const Constant(2))();
  IntColumn get periodTarget => integer().withDefault(const Constant(1))();
  IntColumn get targetDurationSeconds => integer().withDefault(const Constant(1800))();
  DateTimeColumn get pausedAt => dateTime().nullable()();
}

class Completions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// Local calendar day as `yyyy-MM-dd`.
  TextColumn get day => text().withLength(min: 10, max: 10)();

  /// Progress for that day, compared against the habit's dailyTarget.
  IntColumn get amount => integer().withDefault(const Constant(1))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {habitId, day},
      ];
}

@DriftDatabase(tables: [Habits, Completions, DayNotes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(habits, habits.taskType);
            await m.addColumn(habits, habits.twoDayRule);
            await m.addColumn(habits, habits.intervalDays);
            await m.addColumn(habits, habits.periodTarget);
            await m.addColumn(habits, habits.targetDurationSeconds);
            await m.addColumn(habits, habits.pausedAt);
          }
          if (from < 3) {
            await m.createTable(dayNotes);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Stream<List<Habit>> watchActiveHabits() {
    return (select(habits)
          ..where((h) => h.archivedAt.isNull() & h.pausedAt.isNull())
          ..orderBy([
            (h) => OrderingTerm.asc(h.sortOrder),
            (h) => OrderingTerm.asc(h.id),
          ]))
        .watch();
  }

  Stream<List<Habit>> watchPausedHabits() => (select(habits)
        ..where((h) => h.pausedAt.isNotNull() & h.archivedAt.isNull())
        ..orderBy([(h) => OrderingTerm.asc(h.sortOrder)]))
      .watch();

  Stream<List<Habit>> watchArchivedHabits() =>
      (select(habits)..where((h) => h.archivedAt.isNotNull())).watch();

  Stream<List<Completion>> watchAllCompletions() => select(completions).watch();

  Future<int> insertHabit(HabitsCompanion entry) => into(habits).insert(entry);

  Future<void> updateHabit(int id, HabitsCompanion changes) async {
    await (update(habits)..where((h) => h.id.equals(id))).write(changes);
  }

  Future<void> archiveHabit(int id) => updateHabit(id,
      HabitsCompanion(archivedAt: Value(DateTime.now())));

  Future<void> restoreHabit(int id) => updateHabit(id,
      const HabitsCompanion(archivedAt: Value(null), pausedAt: Value(null)));

  Future<void> pauseHabit(int id) => updateHabit(id,
      HabitsCompanion(pausedAt: Value(DateTime.now())));

  Future<void> resumeHabit(int id) =>
      updateHabit(id, const HabitsCompanion(pausedAt: Value(null)));

  Future<void> reorderHabits(List<int> ids) async {
    await transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (update(habits)..where((h) => h.id.equals(ids[i])))
            .write(HabitsCompanion(sortOrder: Value(i)));
      }
    });
  }

  Future<void> deleteHabit(int id) {
    return (delete(habits)..where((h) => h.id.equals(id))).go();
  }

  /// Sets the progress of [habitId] on [day]. An [amount] of 0 clears it.
  Future<String?> getDayNote({required int habitId, required String day}) async {
    final row = await (select(habitDayNotes)..where((n) => n.habitId.equals(habitId) & n.day.equals(day))).getSingleOrNull();
    return row?.note;
  }

  Future<void> setDayNote({required String day, required String note}) async {
    final cleaned = note.trim();
    if (cleaned.isEmpty) {
      await (delete(habitDayNotes)..where((n) => n.habitId.equals(habitId) & n.day.equals(day))).go();
      return;
    }
    await into(habitDayNotes).insert(
      DayNotesCompanion.insert(day: day, note: cleaned),
      onConflict: DoUpdate((old) => DayNotesCompanion(note: Value(cleaned)), target: [habitDayNotes.habitId, habitDayNotes.day]),
    );
  }

  Future<void> setCompletion({
    required int habitId,
    required String day,
    required int amount,
  }) async {
    if (amount <= 0) {
      await (delete(completions)
            ..where((c) => c.habitId.equals(habitId) & c.day.equals(day)))
          .go();
      return;
    }
    await into(completions).insert(
      CompletionsCompanion.insert(
        habitId: habitId,
        day: day,
        amount: Value(amount),
      ),
      onConflict: DoUpdate(
        (old) => CompletionsCompanion(amount: Value(amount)),
        target: [completions.habitId, completions.day],
      ),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'ember.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
