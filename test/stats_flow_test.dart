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

Future<AppDatabase> startApp(WidgetTester tester, {bool timed = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(411, 900);
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.runAsync(
    () => db.insertHabit(
      HabitsCompanion.insert(
        name: 'DSA learning',
        iconKey: 'code',
        colorValue: 0xFFFF6B2C,
        taskType: Value(
          timed ? HabitTaskType.timed.index : HabitTaskType.normal.index,
        ),
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
  return db;
}

Future<void> shutDown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.runAsync(db.close);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> openStats(WidgetTester tester) async {
  await tester.longPress(find.text('DSA learning').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Stats & history'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('open stats, log today on the calendar, undo it, switch charts', (
    tester,
  ) async {
    final db = await startApp(tester);
    await openStats(tester);

    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('Best streak'), findsOneWidget);
    expect(find.text('Completion'), findsOneWidget);
    expect(find.text('Total done'), findsOneWidget);
    expect(find.text('0 days'), findsWidgets);

    // Tap today on the calendar to log it.
    final todayCell = find.byKey(Key('day-${dayKey(startOfDay(DateTime.now()))}'));
    await tester.ensureVisible(todayCell);
    await tester.pumpAndSettle();
    await tester.tap(todayCell);
    await settle(tester);
    expect(find.text('1 day'), findsWidgets);
    expect(find.text('1 done'), findsOneWidget);

    // Tap again to undo.
    await tester.tap(todayCell);
    await settle(tester);
    expect(find.text('0 days'), findsWidgets);
    expect(find.text('0 done'), findsOneWidget);

    // Switch the chart range.
    await tester.ensureVisible(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-week')), findsOneWidget);
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-year')), findsOneWidget);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-month')), findsOneWidget);

    // The habit started today, so there is no earlier month to go back to.
    final prev = tester.widget<IconButton>(find.byKey(const Key('calendar-prev')));
    expect(prev.onPressed, isNull);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('DSA learning'), findsWidgets);
    await shutDown(tester, db);
  });
}
