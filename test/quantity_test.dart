import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/widget_summary.dart';
import 'package:ember/data/backup.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:ember/widgets/widget_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'add_habit_helpers.dart';
import 'home_flow_test.dart' show settle;

void main() {
  late AppDatabase db;
  final today = startOfDay(DateTime.now());

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> water() => db.insertHabit(HabitsCompanion.insert(
        name: 'Water',
        iconKey: 'water',
        colorValue: 0xFF3DA5FF,
        dailyTarget: const Value(1000),
        unitLabel: const Value('ml'),
        stepSize: const Value(250),
        createdAt: Value(DateTime(2026, 1, 1)),
      ));

  Future<HabitView> viewOf(int id) async => (await loadViewsOn(db, today)).firstWhere((v) => v.habit.id == id);

  test('each tap adds one step, shows progress, and a finished habit resets on tap', () async {
    final id = await water();
    final actions = HabitActions(db);
    await actions.tap(await viewOf(id), today);
    var view = await viewOf(id);
    expect(view.countToday, 250);
    expect(view.progressText, '250 / 1000 ml');
    await actions.tap(view, today);
    await actions.tap(await viewOf(id), today);
    await actions.tap(await viewOf(id), today);
    view = await viewOf(id);
    expect(view.countToday, 1000);
    expect(view.isDone, isTrue);
    expect(view.progressText, isNull);
    await actions.tap(view, today);
    expect((await viewOf(id)).countToday, 0);
  });

  test('a widget tap adds one step too', () async {
    final id = await water();
    expect(await logTapFromWidget(db, id, today), isTrue);
    expect(await db.loggedAmount(id, dayKey(today)), 250);
  });

  test('widget rows show the unit', () {
    final summary = buildWidgetSummary(const [
      WidgetHabit(name: 'Water', done: false, count: 500, target: 2000, unit: 'ml', tappable: true),
    ]);
    expect(summary.rows.single.text, '○ Water  500/2000 ml');
  });

  test('plain habits keep a step of one and no unit', () async {
    final id = await db.insertHabit(HabitsCompanion.insert(name: 'Read', iconKey: 'book', colorValue: 0xFFFF6B2C));
    final habit = (await db.select(db.habits).get()).firstWhere((h) => h.id == id);
    expect(habit.stepSize, 1);
    expect(habit.unitLabel, '');
    expect(habit.extraReminders, '');
  });

  test('a backup from before units existed still restores', () async {
    await water();
    final data = jsonDecode(await exportBackupJson(db)) as Map<String, dynamic>;
    for (final h in data['habits'] as List) {
      (h as Map<String, dynamic>)
        ..remove('unitLabel')
        ..remove('stepSize')
        ..remove('extraReminders');
    }
    await restoreBackupJson(db, jsonEncode(data));
    final habit = (await db.select(db.habits).get()).single;
    expect(habit.unitLabel, '');
    expect(habit.stepSize, 1);
  });

  testWidgets('the water quick start creates a habit that counts in ml', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    addTearDown(tester.view.reset);
    final appDb = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(appDb)],
      child: const EmberApp(),
    ));
    await settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.byKey(const Key('template-water')));
    await settle(tester);
    await createHabit(tester);

    final habits = await tester.runAsync(() => appDb.select(appDb.habits).get());
    expect(habits!.single.name, 'Drink water');
    expect(habits.single.dailyTarget, 2000);
    expect(habits.single.unitLabel, 'ml');
    expect(habits.single.stepSize, 250);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(appDb.close);
  });
}
