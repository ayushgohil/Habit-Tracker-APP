import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/reminder_plan.dart';
import 'package:ember/core/streak.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'add_habit_helpers.dart';
import 'home_flow_test.dart' show settle;

void main() {
  group('end date', () {
    test('a habit has ended only on days after its end date', () {
      final end = DateTime(2026, 11, 20);
      expect(hasEndedBefore(null, DateTime(2030)), isFalse);
      expect(hasEndedBefore(end, DateTime(2026, 11, 20, 23)), isFalse);
      expect(hasEndedBefore(end, DateTime(2026, 11, 21)), isTrue);
    });

    test('no reminders are planned after the end date', () {
      final reminders = planReminders(
        now: DateTime(2026, 11, 18, 8),
        schedule: const Schedule(),
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 19),
        hour: 20,
        minute: 0,
        nudgeEnabled: false,
        nudgeHour: 21,
        nudgeMinute: 0,
        doneToday: false,
        days: 5,
      );
      expect(reminders.map((r) => r.when), [
        DateTime(2026, 11, 18, 20),
        DateTime(2026, 11, 19, 20),
      ]);
    });

    test('an ended habit is not listed on later days', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final today = startOfDay(DateTime.now());
      await db.insertHabit(HabitsCompanion.insert(
        name: 'Sprint',
        iconKey: 'code',
        colorValue: 0xFFFF6B2C,
        createdAt: Value(addDays(today, -10)),
        endDate: Value(addDays(today, -2)),
      ));
      expect(await loadViewsOn(db, addDays(today, -3)), hasLength(1));
      expect(await loadViewsOn(db, today), isEmpty);
      await db.close();
    });
  });

  group('add-habit screen', () {
    Future<AppDatabase> start(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 3000);
      addTearDown(tester.view.reset);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const EmberApp(),
      ));
      await settle(tester);
      return db;
    }

    Future<void> stop(WidgetTester tester, AppDatabase db) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await tester.runAsync(db.close);
    }

    testWidgets('the empty home screen points at the add button', (tester) async {
      final db = await start(tester);
      expect(find.byKey(const Key('empty-illustration')), findsOneWidget);
      expect(find.byKey(const Key('empty-arrow')), findsOneWidget);
      await stop(tester, db);
    });

    testWidgets('steps, type cards, presets, end date and the celebration', (tester) async {
      final db = await start(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'Meditate');
      await tester.pump();
      expect(find.descendant(of: find.byKey(const Key('habit-preview')), matching: find.text('Meditate')), findsOneWidget);
      await tester.tap(find.byKey(const Key('primary-action'))); // Continue
      await settle(tester);

      await tester.tap(find.byKey(const Key('type-timed')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('preset-45')));
      await settle(tester);
      expect(find.widgetWithText(TextField, '45'), findsOneWidget);
      await tester.tap(find.byKey(const Key('primary-action')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('schedule-weekdays')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('end-date-switch')));
      await settle(tester);
      expect(find.byKey(const Key('end-date')), findsOneWidget);
      await tester.tap(find.byKey(const Key('primary-action')));
      await settle(tester);
      expect(find.text('Create habit'), findsOneWidget);

      await tester.tap(find.byKey(const Key('primary-action')));
      await settle(tester);
      expect(find.text('Habit created!'), findsOneWidget);
      await tester.tap(find.byKey(const Key('celebration-done')));
      await settle(tester);

      final habit = (await tester.runAsync(() => db.select(db.habits).get()))!.single;
      expect(habit.name, 'Meditate');
      expect(habit.targetDurationSeconds, 45 * 60);
      expect(habit.endDate, isNotNull);
      await stop(tester, db);
    });

    testWidgets('an empty name sends you back to the first step', (tester) async {
      final db = await start(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await openStep(tester, 3);
      await tester.tap(find.byKey(const Key('primary-action')));
      await settle(tester);
      expect(find.text('Name your habit'), findsOneWidget);
      expect((await tester.runAsync(() => db.select(db.habits).get()))!, isEmpty);
      await stop(tester, db);
    });
  });
}
