import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/streak.dart';
import 'package:ember/core/timer.dart';
import 'package:ember/data/backup.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:ember/ui/home/habit_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'home_flow_test.dart' show settle;

void main() {
  tearDown(() => dayStartOffsetMinutes = 0);

  group('streak at risk', () {
    final created = DateTime(2026, 10, 1);
    bool risk(Schedule schedule, Set<String> done, DateTime today,
            {HabitTaskType type = HabitTaskType.normal, bool twoDay = false}) =>
        streakAtRisk(
          schedule: schedule,
          doneDays: done,
          createdAt: created,
          today: today,
          taskType: type,
          twoDayRule: twoDay,
        );

    test('a daily habit with a streak is at risk until it is done today', () {
      const daily = Schedule();
      final done = {'2026-11-17', '2026-11-18'};
      expect(risk(daily, done, DateTime(2026, 11, 19)), isTrue);
      expect(risk(daily, {...done, '2026-11-19'}, DateTime(2026, 11, 19)), isFalse);
    });

    test('with no streak there is nothing to lose', () {
      expect(risk(const Schedule(), {'2026-11-10'}, DateTime(2026, 11, 19)), isFalse);
    });

    test('a weekday habit is not at risk on its day off', () {
      final weekdays = Schedule(type: ScheduleType.weekdays, weekdayMask: 0x1F); // Mon-Fri
      final done = {'2026-11-19', '2026-11-20'}; // Thu, Fri
      expect(risk(weekdays, done, DateTime(2026, 11, 21)), isFalse); // Saturday
      expect(risk(weekdays, done, DateTime(2026, 11, 23)), isTrue); // Monday
    });

    test('a times-a-week habit is only at risk once it cannot afford a day off', () {
      const threeTimes = Schedule(type: ScheduleType.timesPerWeek, timesPerWeek: 3);
      final lastWeek = {'2026-11-02', '2026-11-04', '2026-11-06'};
      expect(risk(threeTimes, lastWeek, DateTime(2026, 11, 11)), isFalse); // Wed, 0 of 3, 4 days left
      expect(risk(threeTimes, {...lastWeek, '2026-11-09'}, DateTime(2026, 11, 14)), isTrue); // Sat, 1 of 3, 1 day left
      expect(risk(threeTimes, {...lastWeek, '2026-11-09', '2026-11-10', '2026-11-12'}, DateTime(2026, 11, 14)), isFalse);
    });

    test('the 2-day rule forgives one miss, so only a second miss is at risk', () {
      const daily = Schedule();
      expect(risk(daily, {'2026-11-16', '2026-11-17', '2026-11-18'}, DateTime(2026, 11, 19), type: HabitTaskType.negative, twoDay: true), isFalse);
      expect(risk(daily, {'2026-11-16', '2026-11-17'}, DateTime(2026, 11, 19), type: HabitTaskType.negative, twoDay: true), isTrue);
    });
  });

  group('timers across the day change', () {
    test('a session over midnight is shared between both days', () {
      final shares = timerShares(
        '2026-11-18',
        TimerState(bankedSeconds: 300, runningSince: DateTime(2026, 11, 18, 23, 50)),
        DateTime(2026, 11, 19, 0, 20),
      );
      expect(shares, {'2026-11-18': 900, '2026-11-19': 1200});
    });

    test('it follows a custom day start', () {
      dayStartOffsetMinutes = 120; // the day changes at 2am
      final shares = timerShares(
        '2026-11-18',
        TimerState(runningSince: DateTime(2026, 11, 19, 1, 0)),
        DateTime(2026, 11, 19, 3, 0),
      );
      expect(shares, {'2026-11-18': 3600, '2026-11-19': 3600});
    });

    test('a timer that stays inside one day is not split', () {
      final shares = timerShares(
        '2026-11-18',
        TimerState(bankedSeconds: 60, runningSince: DateTime(2026, 11, 18, 10)),
        DateTime(2026, 11, 18, 10, 30),
      );
      expect(shares, {'2026-11-18': 1860});
    });

    test('saving a timer that crossed midnight credits both days', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final id = await db.insertHabit(HabitsCompanion.insert(
        name: 'Study',
        iconKey: 'book',
        colorValue: 0xFF5E9BFF,
        taskType: Value(HabitTaskType.timed.index),
        createdAt: Value(DateTime(2026, 11, 1)),
      ));
      await db.startTimer(id, DateTime(2026, 11, 18, 23, 50));
      final saved = await db.finishTimer(id, DateTime(2026, 11, 19, 0, 20));
      expect(saved, 1800);
      final rows = {for (final c in await db.select(db.completions).get()) c.day: c.amount};
      expect(rows, {'2026-11-18': 600, '2026-11-19': 1200});
      await db.close();
    });
  });

  group('limit habits (negative timers)', () {
    late AppDatabase db;
    final today = startOfDay(DateTime.now());
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> limit() => db.insertHabit(HabitsCompanion.insert(
          name: 'Social media',
          iconKey: 'phone',
          colorValue: 0xFFFF5A5F,
          taskType: Value(HabitTaskType.timed.index),
          targetDurationSeconds: const Value(1800),
          limitMode: const Value(true),
          createdAt: Value(addDays(today, -3)),
        ));

    Future<HabitView> view(int id) async =>
        (await loadViewsOn(db, today)).firstWhere((v) => v.habit.id == id);

    test('a limit habit is done until the time used passes the limit', () async {
      final id = await limit();
      var v = await view(id);
      expect(v.isDone, isTrue);
      expect(v.streak.length, 4);
      expect(v.progressText, 'Used 0:00 of 30:00');

      await db.setCompletion(habitId: id, day: dayKey(today), amount: 1800);
      expect((await view(id)).isDone, isTrue); // exactly at the limit is fine

      await db.setCompletion(habitId: id, day: dayKey(today), amount: 1801);
      v = await view(id);
      expect(v.isDone, isFalse);
      expect(v.streak.length, 3); // today no longer counts, yesterday's days still do
      expect(v.atRisk, isFalse);
    });

    test('days that went over the limit break the streak', () async {
      final id = await limit();
      await db.setCompletion(habitId: id, day: dayKey(addDays(today, -1)), amount: 3600);
      final v = await view(id);
      expect(v.streak.length, 1); // only today, which is still under
    });

    test('a backup without limit mode restores as a normal habit', () async {
      await limit();
      final data = jsonDecode(await exportBackupJson(db)) as Map<String, dynamic>;
      for (final h in data['habits'] as List) {
        (h as Map<String, dynamic>).remove('limitMode');
      }
      await restoreBackupJson(db, jsonEncode(data));
      expect((await db.select(db.habits).get()).single.limitMode, isFalse);
    });
  });

  testWidgets('the tile shows a warning while skipping today would end the streak', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 900);
    addTearDown(tester.view.reset);
    final appDb = AppDatabase.forTesting(NativeDatabase.memory());
    final today = startOfDay(DateTime.now());
    await tester.runAsync(() async {
      final id = await appDb.insertHabit(HabitsCompanion.insert(
        name: 'Stretch',
        iconKey: 'stretch',
        colorValue: 0xFF7BD389,
        createdAt: Value(addDays(today, -5)),
      ));
      for (final back in [1, 2]) {
        await appDb.setCompletion(habitId: id, day: dayKey(addDays(today, -back)), amount: 1);
      }
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(appDb)],
      child: const EmberApp(),
    ));
    await settle(tester);
    expect(find.byKey(const Key('streak-at-risk')), findsOneWidget);

    await tester.tap(find.byType(HabitTile).first);
    await settle(tester);
    expect(find.byKey(const Key('streak-at-risk')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(appDb.close);
  });
}
