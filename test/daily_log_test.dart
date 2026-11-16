import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ember/data/database.dart';

void main() {
  late AppDatabase database;
  late int habitId;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    habitId = await database.insertHabit(
      HabitsCompanion.insert(
        name: 'Read',
        iconKey: 'book',
        colorValue: 0xFFFF6B2C,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('daily notes are saved independently for each date', () async {
    await database.setDayNote(habitId: habitId, day: '2026-11-15', note: 'Felt focused');
    await database.setDayNote(habitId: habitId, day: '2026-11-16', note: 'Read before work');

    expect(await database.getDayNote(habitId: habitId, day: '2026-11-15'), 'Felt focused');
    expect(await database.getDayNote(habitId: habitId, day: '2026-11-16'), 'Read before work');
  });

  test('saving a blank note removes that day note only', () async {
    await database.setDayNote(habitId: habitId, day: '2026-11-15', note: 'Keep this');
    await database.setDayNote(habitId: habitId, day: '2026-11-16', note: 'Remove this');

    await database.setDayNote(habitId: habitId, day: '2026-11-16', note: '  ');

    expect(await database.getDayNote(habitId: habitId, day: '2026-11-15'), 'Keep this');
    expect(await database.getDayNote(habitId: habitId, day: '2026-11-16'), isNull);
  });

  test('completion can be edited and undone without affecting another day', () async {
    await database.setCompletion(habitId: habitId, day: '2026-11-15', amount: 1);
    await database.setCompletion(habitId: habitId, day: '2026-11-16', amount: 2);
    await database.setCompletion(habitId: habitId, day: '2026-11-16', amount: 0);

    final rows = await database.select(database.completions).get();
    expect(rows, hasLength(1));
    expect(rows.single.day, '2026-11-15');
    expect(rows.single.amount, 1);
  });

  test('reordering persists the supplied habit order', () async {
    final secondId = await database.insertHabit(
      HabitsCompanion.insert(
        name: 'Walk',
        iconKey: 'walk',
        colorValue: 0xFF5E9BFF,
        sortOrder: const Value(1),
      ),
    );
    await database.reorderHabits([secondId, habitId]);

    final habits = await database.watchActiveHabits().first;
    expect(habits.map((habit) => habit.id).toList(), [secondId, habitId]);
  });
}
