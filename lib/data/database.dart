import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

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

@DriftDatabase(tables: [Habits, Completions])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Stream<List<Habit>> watchActiveHabits() {
    return (select(habits)
          ..where((h) => h.archivedAt.isNull())
          ..orderBy([
            (h) => OrderingTerm.asc(h.sortOrder),
            (h) => OrderingTerm.asc(h.id),
          ]))
        .watch();
  }

  Stream<List<Completion>> watchAllCompletions() => select(completions).watch();

  Future<int> insertHabit(HabitsCompanion entry) => into(habits).insert(entry);

  Future<void> archiveHabit(int id) {
    return (update(habits)..where((h) => h.id.equals(id)))
        .write(HabitsCompanion(archivedAt: Value(DateTime.now())));
  }

  Future<void> deleteHabit(int id) {
    return (delete(habits)..where((h) => h.id.equals(id))).go();
  }

  /// Sets the progress of [habitId] on [day]. An [amount] of 0 clears it.
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
