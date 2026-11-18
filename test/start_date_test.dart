import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/core/day.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasStartedBy', () {
    final start = DateTime(2026, 11, 17, 9, 20);

    test('is false on the day before the start', () {
      expect(hasStartedBy(start, DateTime(2026, 11, 16)), isFalse);
    });

    test('is true on the start day, whatever the time of day', () {
      expect(hasStartedBy(start, DateTime(2026, 11, 17)), isTrue);
      expect(hasStartedBy(start, DateTime(2026, 11, 17, 23, 59)), isTrue);
    });

    test('is true on later days', () {
      expect(hasStartedBy(start, DateTime(2026, 11, 18)), isTrue);
    });
  });

  test('a habit is not listed on days before it started', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await db.insertHabit(
      HabitsCompanion.insert(
        name: 'DSA learning',
        iconKey: 'code',
        colorValue: 0xFFFF6B2C,
        createdAt: Value(DateTime(2026, 11, 17)),
      ),
    );
    await container.read(habitsProvider.future);
    await container.read(completionsProvider.future);
    await container.read(goalsProvider.future);

    final today = container.read(todayProvider.notifier);

    today.state = DateTime(2026, 11, 16);
    expect(container.read(habitViewsProvider).valueOrNull, isEmpty);

    today.state = DateTime(2026, 11, 17);
    expect(container.read(habitViewsProvider).valueOrNull, hasLength(1));

    today.state = DateTime(2026, 11, 18);
    expect(container.read(habitViewsProvider).valueOrNull, hasLength(1));
  });
}
