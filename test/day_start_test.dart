import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/day.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:ember/widgets/widget_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_flow_test.dart' show settle;

void main() {
  tearDown(() => dayStartOffsetMinutes = 0);

  test('by default the day starts at midnight', () {
    expect(currentDay(DateTime(2026, 11, 20, 0, 30)), DateTime(2026, 11, 20));
    expect(currentDayKey(DateTime(2026, 11, 20, 23, 59)), '2026-11-20');
  });

  test('with a 3am start, the small hours still belong to the day before', () {
    dayStartOffsetMinutes = 180;
    expect(currentDayKey(DateTime(2026, 11, 20, 1, 30)), '2026-11-19');
    expect(currentDayKey(DateTime(2026, 11, 20, 2, 59)), '2026-11-19');
    expect(currentDayKey(DateTime(2026, 11, 20, 3, 0)), '2026-11-20');
    expect(currentDay(DateTime(2026, 11, 1, 1, 0)), DateTime(2026, 10, 31));
  });

  test('a widget tap in the small hours logs the previous day', () async {
    dayStartOffsetMinutes = 180;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final id = await db.insertHabit(HabitsCompanion.insert(
      name: 'Read',
      iconKey: 'book',
      colorValue: 0xFFFF6B2C,
      createdAt: Value(DateTime(2026, 1, 1)),
    ));
    final day = startOfDay(yesterday);
    expect(await logTapFromWidget(db, id, day), isTrue);
    expect(await db.loggedAmount(id, dayKey(day)), 1);
  });

  testWidgets('choosing a day start moves today and is remembered', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const EmberApp(),
    ));
    await settle(tester);

    await tester.tap(find.byKey(const Key('appearance-button')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('day-start-3')));
    await tester.tap(find.byKey(const Key('day-start-3')));
    await settle(tester);

    expect(dayStartOffsetMinutes, 180);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getInt('day_start_minutes'), 180);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}
