import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/habit_templates.dart';
import 'package:ember/core/streak.dart';
import 'package:ember/core/timer.dart';
import 'package:ember/data/backup.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'home_flow_test.dart' show settle;

void main() {
  const pomodoro = SessionPlan(goalSeconds: 6000, sessionSeconds: 1500); // 4 x 25 min

  test('a goal splits into equal sessions and tracks the current one', () {
    expect(pomodoro.isSplit, isTrue);
    expect(pomodoro.count, 4);
    expect(pomodoro.sessionAt(0), 1);
    expect(pomodoro.sessionAt(1499), 1);
    expect(pomodoro.sessionAt(1500), 2);
    expect(pomodoro.sessionAt(5999), 4);
    expect(pomodoro.sessionAt(6000), 4);
    expect(pomodoro.secondsIntoSession(1800), 300);
    expect(pomodoro.sessionProgress(750), 0.5);
  });

  test('the last session is shorter when the goal does not divide evenly', () {
    const plan = SessionPlan(goalSeconds: 3600, sessionSeconds: 1500);
    expect(plan.count, 3);
    expect(plan.lengthOf(1), 1500);
    expect(plan.lengthOf(3), 600);
    expect(plan.secondsIntoSession(3300), 300);
  });

  test('a goal with no session length is one session', () {
    const plan = SessionPlan(goalSeconds: 1800, sessionSeconds: 0);
    expect(plan.isSplit, isFalse);
    expect(plan.count, 1);
    expect(plan.sessionAt(900), 1);
    expect(plan.alertsFrom(0).map((a) => a.secondsFromNow), [1800]);
    expect(plan.alertsFrom(0).single.isGoal, isTrue);
  });

  test('alerts list each session end still ahead, the last being the goal', () {
    final alerts = pomodoro.alertsFrom(1800);
    expect(alerts.map((a) => a.secondsFromNow), [1200, 2700, 4200]);
    expect(alerts.map((a) => a.session), [2, 3, 4]);
    expect(alerts.map((a) => a.isGoal), [false, false, true]);
    expect(pomodoro.alertsFrom(6000), isEmpty);
  });

  test('session length is dropped when not shorter than the goal and floored to 20 sessions', () {
    expect(normalizeSessionSeconds(1800, 0), 0);
    expect(normalizeSessionSeconds(1800, 1800), 0);
    expect(normalizeSessionSeconds(1800, 2400), 0);
    expect(normalizeSessionSeconds(6000, 1500), 1500);
    expect(normalizeSessionSeconds(6000, 60), 300); // 6000 / 20
  });

  test('brushing and focus templates are split timers', () {
    final brush = habitTemplates.firstWhere((t) => t.id == 'brush');
    expect(brush.taskType, HabitTaskType.timed);
    expect(brush.target, 6);
    expect(brush.sessionMinutes, 3);
    final focus = habitTemplates.firstWhere((t) => t.id == 'focus');
    expect(focus.target, 100);
    expect(focus.sessionMinutes, 25);
  });

  group('with a database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> focus({int sessionSeconds = 1500}) => db.insertHabit(HabitsCompanion.insert(
          name: 'Focus',
          iconKey: 'timer',
          colorValue: 0xFFFF7043,
          taskType: Value(HabitTaskType.timed.index),
          targetDurationSeconds: const Value(6000),
          sessionSeconds: Value(sessionSeconds),
        ));

    test('a running timer reports every session end and counts what is already logged', () async {
      final id = await focus();
      final now = DateTime.now();
      expect(await db.timerAlerts(id, now), isEmpty); // no timer yet

      await db.startTimer(id, now);
      var alerts = await db.timerAlerts(id, now);
      expect(alerts.map((a) => a.secondsFromNow), [1500, 3000, 4500, 6000]);

      alerts = await db.timerAlerts(id, now.add(const Duration(minutes: 30)));
      expect(alerts.map((a) => a.secondsFromNow), [1200, 2700, 4200]);

      await db.pauseTimer(id, now.add(const Duration(minutes: 5)));
      expect(await db.timerAlerts(id, now.add(const Duration(minutes: 5))), isEmpty);
    });

    test('habits start with a single session', () async {
      final id = await db.insertHabit(HabitsCompanion.insert(name: 'Read', iconKey: 'book', colorValue: 0xFFFF6B2C));
      expect((await db.select(db.habits).get()).firstWhere((h) => h.id == id).sessionSeconds, 0);
    });

    test('session length survives a backup, and old backups restore without it', () async {
      await focus();
      final data = jsonDecode(await exportBackupJson(db)) as Map<String, dynamic>;
      await restoreBackupJson(db, jsonEncode(data));
      expect((await db.select(db.habits).get()).single.sessionSeconds, 1500);

      for (final h in data['habits'] as List) {
        (h as Map<String, dynamic>).remove('sessionSeconds');
      }
      await restoreBackupJson(db, jsonEncode(data));
      expect((await db.select(db.habits).get()).single.sessionSeconds, 0);
    });
  });

  testWidgets('splitting a timed habit into sessions is saved from the New habit screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 900);
    addTearDown(tester.view.reset);
    final appDb = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(appDb)],
      child: const EmberApp(),
    ));
    await settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.byKey(const Key('template-read'))); // timed, 20 minutes
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('session-field')));
    await tester.enterText(find.byKey(const Key('session-field')), '5');
    await tester.pump();
    expect(find.byKey(const Key('session-summary')), findsOneWidget);
    expect(find.text('4 sessions of 5 min. You get an alert as each one ends.'), findsOneWidget);

    await tester.ensureVisible(find.text('Create habit'));
    await tester.tap(find.text('Create habit'));
    await settle(tester);

    final habits = await tester.runAsync(() => appDb.select(appDb.habits).get());
    expect(habits!.single.targetDurationSeconds, 1200);
    expect(habits.single.sessionSeconds, 300);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(appDb.close);
  });
}
