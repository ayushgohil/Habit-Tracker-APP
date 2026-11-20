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

  /// Index into `HealthMetric`; non-zero habits are filled in from Health Connect.
  IntColumn get healthMetric => integer().withDefault(const Constant(0))();
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

/// The goal and schedule a habit has had, each from the day it took effect.
/// The row with the latest [effectiveFrom] not after a day is the goal for that
/// day, so changing a goal never rewrites past days.
class HabitGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// Local calendar day (`yyyy-MM-dd`) this goal starts to apply.
  TextColumn get effectiveFrom => text().withLength(min: 10, max: 10)();

  /// Taps for a normal habit, seconds for a timed one.
  IntColumn get target => integer()();
  IntColumn get scheduleType => integer().withDefault(const Constant(0))();
  IntColumn get weekdayMask => integer().withDefault(const Constant(127))();
  IntColumn get timesPerWeek => integer().withDefault(const Constant(7))();
  IntColumn get intervalDays => integer().withDefault(const Constant(2))();
  IntColumn get periodTarget => integer().withDefault(const Constant(1))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {habitId, effectiveFrom},
      ];
}

@DriftDatabase(tables: [Habits, Completions, DayNotes, ActiveTimers, HabitGoals])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

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
          // Must run before the goal-history step below, which reads every
          // habit column and so needs this one to exist.
          if (from < 7) {
            await m.addColumn(habits, habits.healthMetric);
          }
          if (from < 6) {
            await m.createTable(habitGoals);
            // Every existing habit starts with one goal: what it has now.
            for (final habit in await select(habits).get()) {
              await into(habitGoals).insert(_goalFor(habit, dayKey(habit.createdAt)));
            }
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  SimpleSelectStatement<$HabitsTable, Habit> _activeHabitsQuery() {
    return select(habits)
      ..where((h) => h.archivedAt.isNull() & h.pausedAt.isNull())
      ..orderBy([
        (h) => OrderingTerm.asc(h.sortOrder),
        (h) => OrderingTerm.asc(h.id),
      ]);
  }

  Stream<List<Habit>> watchActiveHabits() => _activeHabitsQuery().watch();

  /// The same habits as [watchActiveHabits], read once.
  Future<List<Habit>> activeHabitsNow() => _activeHabitsQuery().get();

  Stream<List<Habit>> watchPausedHabits() => (select(habits)
        ..where((h) => h.pausedAt.isNotNull() & h.archivedAt.isNull())
        ..orderBy([(h) => OrderingTerm.asc(h.sortOrder)]))
      .watch();

  Stream<List<Habit>> watchArchivedHabits() =>
      (select(habits)..where((h) => h.archivedAt.isNotNull())).watch();

  Stream<List<Habit>> watchAllHabits() => select(habits).watch();

  Stream<List<Completion>> watchAllCompletions() => select(completions).watch();

  Future<int> insertHabit(HabitsCompanion entry) {
    return transaction(() async {
      final id = await into(habits).insert(entry);
      final habit = await (select(habits)..where((h) => h.id.equals(id))).getSingle();
      await into(habitGoals).insert(_goalFor(habit, dayKey(habit.createdAt)));
      return id;
    });
  }

  static HabitGoalsCompanion _goalFor(Habit habit, String from) => HabitGoalsCompanion(
        habitId: Value(habit.id),
        effectiveFrom: Value(from),
        target: Value(habit.taskType == 2 ? habit.targetDurationSeconds : habit.dailyTarget),
        scheduleType: Value(habit.scheduleType),
        weekdayMask: Value(habit.weekdayMask),
        timesPerWeek: Value(habit.timesPerWeek),
        intervalDays: Value(habit.intervalDays),
        periodTarget: Value(habit.periodTarget),
      );

  /// Replaces everything with the given rows (ids are kept). Running timers
  /// are dropped. Habits with no goal rows get one from their current settings.
  Future<void> replaceAllData({
    required List<Habit> habitRows,
    required List<Completion> completionRows,
    required List<DayNote> noteRows,
    required List<HabitGoal> goalRows,
  }) {
    return transaction(() async {
      await delete(activeTimers).go();
      await delete(habitGoals).go();
      await delete(completions).go();
      await delete(dayNotes).go();
      await delete(habits).go();
      await batch((b) {
        b.insertAll(habits, habitRows);
        b.insertAll(completions, completionRows);
        b.insertAll(dayNotes, noteRows);
        b.insertAll(habitGoals, goalRows);
      });
      final withGoals = {for (final g in goalRows) g.habitId};
      for (final habit in habitRows) {
        if (!withGoals.contains(habit.id)) {
          await into(habitGoals).insert(_goalFor(habit, dayKey(habit.createdAt)));
        }
      }
    });
  }

  /// Habits that are filled in from a health app and still in use.
  Future<List<Habit>> healthLinkedHabits() =>
      (select(habits)..where((h) => h.healthMetric.isBiggerThanValue(0) & h.archivedAt.isNull())).get();

  /// What is logged for a habit on a day (`yyyy-MM-dd`); 0 if nothing.
  Future<int> loggedAmount(int habitId, String day) async {
    final row = await (select(completions)
          ..where((c) => c.habitId.equals(habitId) & c.day.equals(day)))
        .getSingleOrNull();
    return row?.amount ?? 0;
  }

  Stream<List<HabitGoal>> watchGoals() => select(habitGoals).watch();

  /// Records the habit's current goal as applying from [from] onwards. Days
  /// before [from] keep the goal they had. A change on the same day replaces
  /// that day's entry.
  Future<void> recordGoalFrom(int habitId, String from) async {
    final habit = await (select(habits)..where((h) => h.id.equals(habitId))).getSingleOrNull();
    if (habit == null) return;
    await into(habitGoals).insert(
      _goalFor(habit, from),
      onConflict: DoUpdate((old) => _goalFor(habit, from), target: [habitGoals.habitId, habitGoals.effectiveFrom]),
    );
  }

  /// Makes the habit's current goal apply to its whole history.
  Future<void> collapseGoals(int habitId) {
    return transaction(() async {
      final habit = await (select(habits)..where((h) => h.id.equals(habitId))).getSingleOrNull();
      if (habit == null) return;
      await (delete(habitGoals)..where((g) => g.habitId.equals(habitId))).go();
      await into(habitGoals).insert(_goalFor(habit, dayKey(habit.createdAt)));
    });
  }

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
        day: Value(currentDayKey(now)),
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

  /// Seconds until a running timer reaches the habit's goal for the day it was
  /// started, counting what was already logged that day. Null if no timer is
  /// running or the goal is already reached.
  Future<int?> secondsUntilGoal(int habitId, DateTime now) async {
    final timer = await getTimer(habitId);
    if (timer == null || timer.runningSince == null) return null;
    final habit = await (select(habits)..where((h) => h.id.equals(habitId))).getSingleOrNull();
    if (habit == null || habit.taskType != 2) return null;
    final logged = await (select(completions)
          ..where((c) => c.habitId.equals(habitId) & c.day.equals(timer.day)))
        .getSingleOrNull();
    final remaining = habit.targetDurationSeconds - (logged?.amount ?? 0) - stateOf(timer).elapsedSeconds(now);
    return remaining > 0 ? remaining : null;
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
