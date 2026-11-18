import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/streak.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

/// Alternates real time (for the database) with fake time (for timers and
/// frames) a few times. Unlike pumpAndSettle it also works while the timer
/// screen's one-second ticker is running, which would never let it settle.
Future<void> pumpBoth(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<(AppDatabase, int)> startApp(
  WidgetTester tester, {
  bool pausedTimer = false,
  int loggedSeconds = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(411, 900);
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final id = await tester.runAsync(
    () => db.insertHabit(
      HabitsCompanion.insert(
        name: 'DSA learning',
        iconKey: 'code',
        colorValue: 0xFFFF6B2C,
        taskType: Value(HabitTaskType.timed.index),
      ),
    ),
  );
  if (loggedSeconds > 0) {
    await tester.runAsync(
      () => db.setCompletion(habitId: id!, day: dayKey(DateTime.now()), amount: loggedSeconds),
    );
  }
  if (pausedTimer) {
    // Seed before the app opens: writing through a database that the running
    // app is already watching from inside runAsync stalls the test.
    await tester.runAsync(() async {
      await db.startTimer(id!, DateTime.now().subtract(const Duration(minutes: 3)));
      await db.pauseTimer(id, DateTime.now());
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const EmberApp(),
    ),
  );
  await settle(tester);
  return (db, id!);
}

Future<void> shutDown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.runAsync(db.close);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  test('finishing a timer adds its time to the day it started', timeout: const Timeout(Duration(seconds: 30)), () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final id = await db.insertHabit(
      HabitsCompanion.insert(name: 'Read', iconKey: 'book', colorValue: 0xFFFF6B2C),
    );
    final start = DateTime.now().subtract(const Duration(minutes: 20));
    await db.startTimer(id, start);
    await db.pauseTimer(id, start.add(const Duration(minutes: 10)));
    await db.startTimer(id, start.add(const Duration(minutes: 15)));

    final seconds = await db.finishTimer(id, start.add(const Duration(minutes: 20)));
    expect(seconds, 15 * 60);
    expect(await db.getTimer(id), isNull);
    final rows = await db.select(db.completions).get();
    expect(rows.single.day, dayKey(start));
    expect(rows.single.amount, 15 * 60);

    // A second timer on the same day adds to it.
    await db.startTimer(id, start);
    await db.finishTimer(id, start.add(const Duration(minutes: 5)));
    expect((await db.select(db.completions).get()).single.amount, 20 * 60);
    await db.close();
  });

  test('discarding a timer saves nothing; deleting the habit removes it', timeout: const Timeout(Duration(seconds: 30)), () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final id = await db.insertHabit(
      HabitsCompanion.insert(name: 'Read', iconKey: 'book', colorValue: 0xFFFF6B2C),
    );
    await db.startTimer(id, DateTime.now());
    await db.discardTimer(id);
    expect(await db.getTimer(id), isNull);
    expect(await db.select(db.completions).get(), isEmpty);

    await db.startTimer(id, DateTime.now());
    await db.deleteHabit(id);
    expect(await db.select(db.activeTimers).get(), isEmpty);
    await db.close();
  });

  testWidgets('start, pause and save a timer from the habit menu', timeout: const Timeout(Duration(seconds: 45)), (tester) async {
    final (db, id) = await startApp(tester);

    await tester.longPress(find.text('DSA learning').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timer'));
    // The timer screen shows a spinner until its streams emit, which needs
    // real async time, so settle() rather than pumpAndSettle().
    await settle(tester);
    expect(find.byKey(const Key('timer-clock')), findsOneWidget);
    expect(find.text('Goal 30:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    await pumpBoth(tester);
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await pumpBoth(tester);
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timer-save')));
    await pumpBoth(tester);
    await settle(tester);
    expect(find.byKey(const Key('timer-clock')), findsNothing);
    expect(find.text('DSA learning'), findsWidgets);
    expect(await tester.runAsync(() => db.getTimer(id)), isNull);

    await shutDown(tester, db);
  });

  test('seconds until the goal count what is already logged', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final id = await db.insertHabit(
      HabitsCompanion.insert(
        name: 'Study',
        iconKey: 'book',
        colorValue: 0xFFFF6B2C,
        taskType: Value(HabitTaskType.timed.index),
        targetDurationSeconds: const Value(3600),
      ),
    );
    final now = DateTime.now();
    await db.setCompletion(habitId: id, day: dayKey(now), amount: 1800);
    expect(await db.secondsUntilGoal(id, now), isNull); // no timer yet

    await db.startTimer(id, now);
    expect(await db.secondsUntilGoal(id, now), 1800);
    expect(await db.secondsUntilGoal(id, now.add(const Duration(minutes: 10))), 1200);
    expect(await db.secondsUntilGoal(id, now.add(const Duration(minutes: 31))), isNull);

    await db.pauseTimer(id, now.add(const Duration(minutes: 5)));
    expect(await db.secondsUntilGoal(id, now.add(const Duration(minutes: 5))), isNull);
    await db.close();
  });

  test('archiving a habit saves its running timer and removes it', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final id = await db.insertHabit(
      HabitsCompanion.insert(
        name: 'Study',
        iconKey: 'book',
        colorValue: 0xFFFF6B2C,
        taskType: Value(HabitTaskType.timed.index),
      ),
    );
    await db.startTimer(id, DateTime.now().subtract(const Duration(minutes: 7)));
    await HabitActions(db).archive(id);
    expect(await db.getTimer(id), isNull);
    final rows = await db.select(db.completions).get();
    expect(rows.single.amount, greaterThanOrEqualTo(7 * 60));
    await db.close();
  });

  testWidgets('the ring starts from time already logged today', timeout: const Timeout(Duration(seconds: 45)), (tester) async {
    final (db, id) = await startApp(tester, pausedTimer: true, loggedSeconds: 1500);
    await tester.tap(find.byKey(Key('timer-banner-$id')));
    await pumpBoth(tester);
    expect(find.text('25:00 already logged'), findsOneWidget);
    expect(find.text('Goal 30:00'), findsOneWidget);
    await shutDown(tester, db);
  });

  testWidgets('a paused timer shows on Home and can be discarded', timeout: const Timeout(Duration(seconds: 45)), (tester) async {
    final (db, id) = await startApp(tester, pausedTimer: true);

    expect(find.byKey(Key('timer-banner-$id')), findsOneWidget);
    await tester.tap(find.byKey(Key('timer-banner-$id')));
    await pumpBoth(tester);
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timer-discard')));
    await pumpBoth(tester);
    await settle(tester);
    expect(find.byKey(Key('timer-banner-$id')), findsNothing);
    expect(await tester.runAsync(() => db.getTimer(id)), isNull);

    await shutDown(tester, db);
  });
}
