import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/day.dart';
import '../core/timer.dart';

part 'database.g.dart';

class DayNotes extends Table {
  TextColumn get day => text().withLength(min: 10, max: 10)();
  TextColumn get note => text()();

  @override
  Set<Column> get primaryKey => {day};
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
  BoolColumn get reminderEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get reminderHour => integer().withDefault(const Constant(20))();
  IntColumn get reminderMinute => integer().withDefault(const Constant(0))();
  BoolColumn get partialNudgeEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get partialNudgeHour => integer().withDefault(const Constant(21))();
  IntColumn get partialNudgeMinute => integer().withDefault(const Constant(0))();
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

/// A timer that is running or paused for a timed habit. At most one per habit.
class ActiveTimers extends Table {
  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// The day (`yyyy-MM-dd`) the timer was started; the time is saved to it.
  TextColumn get day => text().withLength(min: 10, max: 10)();

  /// Seconds run before the last pause.
  IntColumn get bankedSeconds => integer().withDefault(const Constant(0))();

  /// When it last started running. Null while paused.
  DateTimeColumn get runningSince => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {habitId};
}

@DriftDatabase(tables: [Habits, Completions, DayNotes, ActiveTimers])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

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
          if (from < 4) {
            await m.addColumn(habits, habits.reminderEnabled);
            await m.addColumn(habits, habits.reminderHour);
            await m.addColumn(habits, habits.reminderMinute);
            await m.addColumn(habits, habits.partialNudgeEnabled);
            await m.addColumn(habits, habits.partialNudgeHour);
            await m.addColumn(habits, habits.partialNudgeMinute);
          }
          if (from < 5) {
            await m.createTable(activeTimers);
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

  Stream<List<Habit>> watchAllHabits() => select(habits).watch();

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
  Future<String?> getDayNote({required String day}) async {
    final row = await (select(dayNotes)..where((n) => n.day.equals(day))).getSingleOrNull();
    return row?.note;
  }

  Future<void> setDayNote({required String day, required String note}) async {
    final cleaned = note.trim();
    if (cleaned.isEmpty) {
      await (delete(dayNotes)..where((n) => n.day.equals(day))).go();
      return;
    }
    await into(dayNotes).insert(
      DayNotesCompanion.insert(day: day, note: cleaned),
      onConflict: DoUpdate(
        (old) => DayNotesCompanion(note: Value(cleaned)),
        target: [dayNotes.day],
      ),
    );
  }

  Stream<List<ActiveTimer>> watchTimers() => select(activeTimers).watch();

  Future<ActiveTimer?> getTimer(int habitId) =>
      (select(activeTimers)..where((t) => t.habitId.equals(habitId))).getSingleOrNull();

  static TimerState stateOf(ActiveTimer row) =>
      TimerState(bankedSeconds: row.bankedSeconds, runningSince: row.runningSince);

  /// Starts a timer for [habitId], or resumes a paused one.
  Future<void> startTimer(int habitId, DateTime now) async {
    final existing = await getTimer(habitId);
    if (existing == null) {
      await into(activeTimers).insert(ActiveTimersCompanion(
        habitId: Value(habitId),
        day: Value(dayKey(now)),
        runningSince: Value(now),
      ));
      return;
    }
    final next = stateOf(existing).start(now);
    await (update(activeTimers)..where((t) => t.habitId.equals(habitId)))
        .write(ActiveTimersCompanion(runningSince: Value(next.runningSince)));
  }

  Future<void> pauseTimer(int habitId, DateTime now) async {
    final existing = await getTimer(habitId);
    if (existing == null) return;
    final next = stateOf(existing).pause(now);
    await (update(activeTimers)..where((t) => t.habitId.equals(habitId))).write(
      ActiveTimersCompanion(
        bankedSeconds: Value(next.bankedSeconds),
        runningSince: const Value(null),
      ),
    );
  }

  Future<void> discardTimer(int habitId) =>
      (delete(activeTimers)..where((t) => t.habitId.equals(habitId))).go();

  /// Adds the timer's time to the day it was started on and removes it.
  /// Returns the seconds saved (0 if there was no timer).
  Future<int> finishTimer(int habitId, DateTime now) {
    return transaction(() async {
      final existing = await getTimer(habitId);
      if (existing == null) return 0;
      final seconds = stateOf(existing).elapsedSeconds(now);
      if (seconds > 0) {
        final row = await (select(completions)
              ..where((c) => c.habitId.equals(habitId) & c.day.equals(existing.day)))
            .getSingleOrNull();
        await setCompletion(
          habitId: habitId,
          day: existing.day,
          amount: (row?.amount ?? 0) + seconds,
        );
      }
      await discardTimer(habitId);
      return seconds;
    });
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
