import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/health.dart';
import 'package:ember/core/streak.dart';
import 'package:ember/data/backup.dart';
import 'package:ember/data/database.dart';
import 'package:ember/health/health_sync.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHealth implements HealthSource {
  FakeHealth(this.values, {this.allowed = true});
  final Map<String, int?> values; // "metric:yyyy-MM-dd" -> value
  bool allowed;
  int reads = 0;

  @override
  Future<bool> hasPermission(HealthMetric metric) async => allowed;
  @override
  Future<bool> requestPermission(HealthMetric metric) async => allowed;
  @override
  Future<int?> amountForDay(HealthMetric metric, DateTime day) async {
    reads++;
    return values['${metric.name}:${dayKey(day)}'];
  }
}

void main() {
  late AppDatabase db;
  final today = startOfDay(DateTime.now());

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> stepsHabit({DateTime? created, bool archived = false}) async {
    final id = await db.insertHabit(
      HabitsCompanion.insert(
        name: 'Walk',
        iconKey: 'run',
        colorValue: 0xFFFF6B2C,
        createdAt: Value(created ?? addDays(today, -10)),
        dailyTarget: const Value(8000),
        healthMetric: Value(HealthMetric.steps.index),
      ),
    );
    if (archived) await db.archiveHabit(id);
    return id;
  }

  Future<int> amountOn(int id, DateTime day) async {
    final row = await (db.select(db.completions)
          ..where((c) => c.habitId.equals(id) & c.day.equals(dayKey(day))))
        .getSingleOrNull();
    return row?.amount ?? 0;
  }

  test('fills the last days from the health app', () async {
    final id = await stepsHabit();
    final health = FakeHealth({
      'steps:${dayKey(today)}': 9000,
      'steps:${dayKey(addDays(today, -1))}': 4200,
      'steps:${dayKey(addDays(today, -2))}': 0,
    });
    final changed = await HealthSync(db, health).syncNow();
    expect(changed, 2);
    expect(await amountOn(id, today), 9000);
    expect(await amountOn(id, addDays(today, -1)), 4200);
    expect(await amountOn(id, addDays(today, -2)), 0);
  });

  test('never lowers a day and does nothing when nothing changed', () async {
    final id = await stepsHabit();
    await db.setCompletion(habitId: id, day: dayKey(today), amount: 12000);
    final health = FakeHealth({'steps:${dayKey(today)}': 9000});
    final sync = HealthSync(db, health);
    expect(await sync.syncNow(), 0);
    expect(await amountOn(id, today), 12000);
  });

  test('skips days before the habit started', () async {
    final id = await stepsHabit(created: today);
    final health = FakeHealth({
      'steps:${dayKey(today)}': 5000,
      'steps:${dayKey(addDays(today, -1))}': 7000,
    });
    await HealthSync(db, health).syncNow();
    expect(await amountOn(id, today), 5000);
    expect(await amountOn(id, addDays(today, -1)), 0);
    expect(health.reads, 1);
  });

  test('does nothing without permission, for manual and archived habits', () async {
    final linked = await stepsHabit();
    final archived = await stepsHabit(archived: true);
    await db.insertHabit(HabitsCompanion.insert(name: 'Manual', iconKey: 'x', colorValue: 1));
    final denied = FakeHealth({'steps:${dayKey(today)}': 9000}, allowed: false);
    expect(await HealthSync(db, denied).syncNow(), 0);
    expect(denied.reads, 0);

    final allowed = FakeHealth({'steps:${dayKey(today)}': 9000});
    await HealthSync(db, allowed).syncNow();
    expect(await amountOn(linked, today), 9000);
    expect(await amountOn(archived, today), 0);
    expect(await db.select(db.completions).get(), hasLength(1));
  });

  test('a value that could not be read leaves the day alone', () async {
    final id = await stepsHabit();
    final health = FakeHealth({'steps:${dayKey(today)}': null});
    expect(await HealthSync(db, health).syncNow(), 0);
    expect(await amountOn(id, today), 0);
  });

  test('sleep habits store seconds', () async {
    final id = await db.insertHabit(
      HabitsCompanion.insert(
        name: 'Sleep',
        iconKey: 'bed',
        colorValue: 1,
        createdAt: Value(addDays(today, -3)),
        taskType: Value(HabitTaskType.timed.index),
        targetDurationSeconds: const Value(8 * 3600),
        healthMetric: Value(HealthMetric.sleep.index),
      ),
    );
    final health = FakeHealth({'sleep:${dayKey(today)}': 7 * 3600 + 30 * 60});
    await HealthSync(db, health).syncNow();
    expect(await amountOn(id, today), 27000);
  });

  test('a backup made before health links existed still restores', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    await source.insertHabit(HabitsCompanion.insert(name: 'Old', iconKey: 'x', colorValue: 1));
    final json = await exportBackupJson(source);
    final withoutColumn = json.replaceAll(RegExp(r'\s*"healthMetric": \d+,?'), '');
    expect(withoutColumn.contains('healthMetric'), isFalse);

    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await restoreBackupJson(target, withoutColumn);
    final habit = (await target.select(target.habits).get()).single;
    expect(habit.name, 'Old');
    expect(habit.healthMetric, 0);
  });
}
