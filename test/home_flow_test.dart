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

/// Lets real async work (the in-memory database) run, then redraws.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

/// Starts the app on a phone-sized screen with an in-memory database.
Future<AppDatabase> startApp(
  WidgetTester tester, {
  bool withHabit = false,
  bool timed = false,
}) async {
  // A typical phone: 411 x 800 logical pixels.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(411, 800);
  addTearDown(tester.view.reset);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  if (withHabit) {
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
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const EmberApp(),
    ),
  );
  await settle(tester);
  return db;
}

/// Tears the app down before closing the database.
Future<void> shutDown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.runAsync(db.close);
  await tester.pump(const Duration(seconds: 1));
}

/// Opens the long-press menu of the habit in the grid.
Future<void> openMenu(WidgetTester tester) async {
  await tester.longPress(find.text('DSA learning').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create a habit, open its menu, pause it and resume it', (
    tester,
  ) async {
    final db = await startApp(tester);
    expect(find.text('Light your first ember'), findsOneWidget);

    // Create a habit through the form.
    await tester.tap(find.text('Add a habit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'DSA learning');
    await tester.tap(find.text('Create habit'));
    await settle(tester);
    expect(find.text('DSA learning'), findsWidgets);

    // The menu must fit without overflowing, and scroll to the last row.
    await openMenu(tester);
    expect(find.text('Edit habit'), findsOneWidget);
    await tester.ensureVisible(find.text('Delete'));
    await tester.pumpAndSettle();

    // Pause it from the menu.
    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect(find.text('Light your first ember'), findsOneWidget);

    // Bring it back from the habit library.
    await tester.tap(find.byTooltip('Habit library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paused'));
    await tester.pumpAndSettle();
    expect(find.text('DSA learning'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await settle(tester);
    expect(find.text('No paused habits'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('DSA learning'), findsWidgets);

    await shutDown(tester, db);
  });

  testWidgets('log a habit, add a note, view another day, edit the habit', (
    tester,
  ) async {
    final db = await startApp(tester, withHabit: true);
    expect(find.text('DSA learning'), findsWidgets);

    // Log it.
    await tester.tap(find.text('DSA learning').last);
    await settle(tester);
    expect(find.text('DSA learning logged'), findsOneWidget);

    // Add a note for today.
    await tester.tap(find.byTooltip('Daily note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Solved two problems');
    await tester.tap(find.text('Save'));
    await settle(tester);

    // The habit was created today, so it is not there yesterday.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EmberApp)),
    );
    final today = container.read(todayProvider);
    container.read(todayProvider.notifier).state = addDays(today, -1);
    await tester.pumpAndSettle();
    expect(find.text('No habits on this day'), findsOneWidget);
    expect(find.text('DSA learning'), findsNothing);

    await tester.tap(find.text('Back to today'));
    await tester.pumpAndSettle();
    expect(find.text('DSA learning'), findsWidgets);

    // Edit it.
    await openMenu(tester);
    await tester.tap(find.text('Edit habit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'DSA practice');
    await tester.tap(find.text('Save changes'));
    await settle(tester);
    expect(find.text('DSA practice'), findsWidgets);

    await shutDown(tester, db);
  });

  testWidgets('log time on a timed habit, then clear it', (tester) async {
    final db = await startApp(tester, withHabit: true, timed: true);

    await tester.tap(find.text('DSA learning').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('DSA learning: 10 min logged'), findsOneWidget);

    await tester.tap(find.text('DSA learning').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear logged time'));
    await settle(tester);
    expect(find.text('DSA learning time cleared'), findsOneWidget);

    await shutDown(tester, db);
  });

  testWidgets('archive a habit, restore it, then delete it', (tester) async {
    final db = await startApp(tester, withHabit: true);

    await openMenu(tester);
    await tester.ensureVisible(find.text('Archive'));
    await tester.tap(find.text('Archive'));
    await settle(tester);
    expect(find.text('Light your first ember'), findsOneWidget);

    await tester.tap(find.byTooltip('Habit library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await settle(tester);
    expect(find.text('No archived habits'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('DSA learning'), findsWidgets);

    await openMenu(tester);
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);
    expect(find.text('Light your first ember'), findsOneWidget);

    await shutDown(tester, db);
  });
}
