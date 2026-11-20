import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_flow_test.dart' show settle;

Future<AppDatabase> start(WidgetTester tester, int habits, {Map<String, Object> saved = const {}}) async {
  SharedPreferences.setMockInitialValues(saved);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(411, 800);
  addTearDown(tester.view.reset);
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.runAsync(() async {
    for (var i = 0; i < habits; i++) {
      await db.insertHabit(HabitsCompanion.insert(name: 'Habit $i', iconKey: 'code', colorValue: 0xFFFF6B2C));
    }
  });
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

void main() {
  foldPersistence();
  testWidgets('a few habits: the list is open and can be folded', (tester) async {
    final db = await start(tester, 3);
    expect(find.byType(ReorderableListView), findsOneWidget);
    await tester.tap(find.byKey(const Key('up-next-toggle')));
    await settle(tester);
    expect(find.byType(ReorderableListView), findsNothing);
    await tester.tap(find.byKey(const Key('up-next-toggle')));
    await settle(tester);
    expect(find.byType(ReorderableListView), findsOneWidget);
    await stop(tester, db);
  });

  testWidgets('many habits: the list starts folded and can be opened', (tester) async {
    final db = await start(tester, 6);
    expect(find.byType(ReorderableListView), findsNothing);
    expect(find.text('Habit 5'), findsOneWidget); // still shown as a ring
    await tester.tap(find.byKey(const Key('up-next-toggle')));
    await settle(tester);
    expect(find.byType(ReorderableListView), findsOneWidget);
    await stop(tester, db);
  });
}

void foldPersistence() {
  testWidgets('a saved fold choice is used when the app starts', (tester) async {
    final db = await start(tester, 3, saved: {'up_next_open': false}); // few habits would normally start open
    await tester.pump(const Duration(milliseconds: 50));
    await settle(tester);
    expect(find.byType(ReorderableListView), findsNothing);
    await stop(tester, db);
  });

  testWidgets('folding the list is saved', (tester) async {
    final db = await start(tester, 3);
    await tester.tap(find.byKey(const Key('up-next-toggle')));
    await settle(tester);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('up_next_open'), isFalse);
    await stop(tester, db);
  });
}
