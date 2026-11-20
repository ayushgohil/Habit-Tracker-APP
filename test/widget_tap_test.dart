import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/widget_summary.dart';
import 'package:ember/data/database.dart';
import 'package:ember/widgets/widget_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final today = startOfDay(DateTime.now());

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> add({int target = 1, int taskType = 0, int healthMetric = 0}) => db.insertHabit(HabitsCompanion.insert(
        name: 'Habit',
        iconKey: 'flame',
        colorValue: 0xFFFF6B2C,
        dailyTarget: Value(target),
        taskType: Value(taskType),
        healthMetric: Value(healthMetric),
      ));

  Future<int> logged(int id) => db.loggedAmount(id, dayKey(today));

  test('one tap completes a once-a-day habit and a second tap changes nothing', () async {
    final id = await add();
    expect(await logTapFromWidget(db, id, today), isTrue);
    expect(await logged(id), 1);
    expect(await logTapFromWidget(db, id, today), isFalse);
    expect(await logged(id), 1);
  });

  test('a habit with a higher goal counts up one tap at a time', () async {
    final id = await add(target: 3);
    await logTapFromWidget(db, id, today);
    await logTapFromWidget(db, id, today);
    expect(await logged(id), 2);
    await logTapFromWidget(db, id, today);
    expect(await logged(id), 3);
    expect(await logTapFromWidget(db, id, today), isFalse);
  });

  test('timed and Health Connect habits are left to the app', () async {
    final timed = await add(taskType: 2);
    final health = await add(healthMetric: 1);
    expect(await logTapFromWidget(db, timed, today), isFalse);
    expect(await logTapFromWidget(db, health, today), isFalse);
    expect(await logged(timed), 0);
    expect(await logged(health), 0);
  });

  test('an unknown habit is ignored', () async {
    expect(await logTapFromWidget(db, 999, today), isFalse);
  });

  test('widget rows say which taps log a habit', () {
    final summary = buildWidgetSummary(const [
      WidgetHabit(name: 'Read', done: false, count: 0, target: 1, id: 1, tappable: true),
      WidgetHabit(name: 'Run', done: false, count: 0, target: 1800, timed: true, id: 2),
      WidgetHabit(name: 'Water', done: true, count: 1, target: 1, id: 3, tappable: true),
    ]);
    expect(summary.rows.map((r) => r.tappable), [true, false, false]);
    expect(summary.rows.map((r) => r.id), [1, 2, 3]);
  });
}
