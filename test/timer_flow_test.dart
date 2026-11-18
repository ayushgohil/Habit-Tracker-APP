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

Future<(AppDatabase, int)> startApp(WidgetTester tester) async {
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

  testWidgets('a paused timer shows on Home and can be discarded', timeout: const Timeout(Duration(seconds: 45)), (tester) async {
    final (db, id) = await startApp(tester);
    await tester.runAsync(() async {
    // ignore: avoid_print
    print('TIMERTEST step 1');
      await db.startTimer(id, DateTime.now().subtract(const Duration(minutes: 3)));
      await db.pauseTimer(id, DateTime.now());
    });
    await settle(tester);
    // ignore: avoid_print
    print('TIMERTEST step 2');

    expect(find.byKey(Key('timer-banner-$id')), findsOneWidget);
    // ignore: avoid_print
    print('TIMERTEST step 3');
    await tester.tap(find.byKey(Key('timer-banner-$id')));
    // ignore: avoid_print
    print('TIMERTEST step 4');
    await pumpBoth(tester);
    // ignore: avoid_print
    print('TIMERTEST step 5');
    expect(find.text('Resume'), findsOneWidget);
    // ignore: avoid_print
    print('TIMERTEST step 6');

    await tester.tap(find.byKey(const Key('timer-discard')));
    // ignore: avoid_print
    print('TIMERTEST step 7');
    await pumpBoth(tester);
    // ignore: avoid_print
    print('TIMERTEST step 8');
    await settle(tester);
    // ignore: avoid_print
    print('TIMERTEST step 9');
    expect(find.byKey(Key('timer-banner-$id')), findsNothing);
    // ignore: avoid_print
    print('TIMERTEST step 10');
    expect(await tester.runAsync(() => db.getTimer(id)), isNull);
    // ignore: avoid_print
    print('TIMERTEST step 11');

    await shutDown(tester, db);
    // ignore: avoid_print
    print('TIMERTEST step 12');
  });
}
