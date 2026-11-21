import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/habit_icons.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:ember/theme/ember_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_flow_test.dart' show settle;

void main() {
  test('every theme and icon key is unique and usable', () {
    expect(emberPalettes.map((p) => p.id).toSet().length, emberPalettes.length);
    expect(habitIconEntries.map((e) => e.key).toSet().length, habitIconEntries.length);
    expect(habitIconEntries.length, greaterThan(280));
    expect(paletteById('nope').id, 'ember');
    expect(paletteById('ocean').name, 'Ocean');
    for (final p in emberPalettes) {
      expect(() => emberTheme(p), returnsNormally);
    }
  });

  test('old icon keys still resolve to their icons', () {
    for (final key in ['flame', 'water', 'fitness', 'run', 'walk', 'meditate', 'sleep', 'sun', 'book', 'study', 'write', 'code', 'music', 'food', 'pill', 'clean', 'savings', 'no_phone']) {
      expect(habitIcons.containsKey(key), isTrue, reason: key);
    }
  });

  test('icon search matches names and keywords', () {
    expect(searchHabitIcons('').length, habitIconEntries.length);
    expect(searchHabitIcons('jog').map((e) => e.key), contains('run'));
    expect(searchHabitIcons('MONEY').map((e) => e.key), contains('savings'));
    expect(searchHabitIcons('zzzzzz'), isEmpty);
  });

  Future<AppDatabase> start(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    addTearDown(tester.view.reset);
    addTearDown(() => EmberColors.use(emberPalettes.first));
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

  testWidgets('choosing a look changes the colours and is remembered', (tester) async {
    final db = await start(tester);
    expect(EmberColors.palette.id, 'ember');
    await tester.tap(find.byKey(const Key('appearance-button')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('theme-ocean')));
    await settle(tester);
    expect(EmberColors.palette.id, 'ocean');
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getString('theme_id'), 'ocean');
    await stop(tester, db);
  });

  testWidgets('a saved look is used on the next launch', (tester) async {
    SharedPreferences.setMockInitialValues({'theme_id': 'paper'});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    addTearDown(tester.view.reset);
    addTearDown(() => EmberColors.use(emberPalettes.first));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const EmberApp(),
    ));
    await settle(tester);
    expect(EmberColors.palette.id, 'paper');
    await stop(tester, db);
  });
}
