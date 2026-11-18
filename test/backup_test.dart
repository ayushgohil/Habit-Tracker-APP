import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/streak.dart';
import 'package:ember/data/backup.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase source;
  final today = startOfDay(DateTime.now());

  setUp(() async {
    source = AppDatabase.forTesting(NativeDatabase.memory());
    final run = await source.insertHabit(
      HabitsCompanion.insert(
        name: 'Run, "fast"',
        iconKey: 'run',
        colorValue: 0xFFFF6B2C,
        createdAt: Value(addDays(today, -10)),
        dailyTarget: const Value(2),
      ),
    );
    final study = await source.insertHabit(
      HabitsCompanion.insert(
        name: 'Study',
        iconKey: 'book',
        colorValue: 0xFF42A5F5,
        createdAt: Value(addDays(today, -10)),
        taskType: Value(HabitTaskType.timed.index),
        targetDurationSeconds: const Value(1800),
      ),
    );
    await source.setCompletion(habitId: run, day: dayKey(addDays(today, -2)), amount: 2);
    await source.setCompletion(habitId: study, day: dayKey(addDays(today, -1)), amount: 900);
    await source.setDayNote(day: dayKey(today), note: 'Good day');
    await HabitActions(source).edit(
      id: study,
      name: 'Study',
      iconKey: 'book',
      colorValue: 0xFF42A5F5,
      schedule: const Schedule(),
      dailyTarget: 1,
      taskType: HabitTaskType.timed,
      twoDayRule: false,
      targetDurationSeconds: 3600,
      reminderEnabled: false,
      reminderHour: 20,
      reminderMinute: 0,
      partialNudgeEnabled: false,
      partialNudgeHour: 21,
      partialNudgeMinute: 0,
    );
  });
  tearDown(() => source.close());

  test('a backup restores into an empty database exactly', () async {
    final json = await exportBackupJson(source);
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);

    final summary = await restoreBackupJson(target, json);
    expect(summary.habits, 2);
    expect(summary.days, 2);

    expect(await target.select(target.habits).get(), await source.select(source.habits).get());
    expect(await target.select(target.completions).get(), await source.select(source.completions).get());
    expect(await target.select(target.dayNotes).get(), await source.select(source.dayNotes).get());
    final goals = await target.select(target.habitGoals).get();
    expect(goals, await source.select(source.habitGoals).get());
    expect(goals, hasLength(3)); // two starting goals plus the raised one
  });

  test('restoring replaces what was there and drops running timers', () async {
    final json = await exportBackupJson(source);
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    final other = await target.insertHabit(
      HabitsCompanion.insert(name: 'Other', iconKey: 'x', colorValue: 1),
    );
    await target.setCompletion(habitId: other, day: dayKey(today), amount: 1);
    await target.startTimer(other, DateTime.now());

    await restoreBackupJson(target, json);

    final names = [for (final h in await target.select(target.habits).get()) h.name];
    expect(names, unorderedEquals(['Run, "fast"', 'Study']));
    expect(await target.select(target.activeTimers).get(), isEmpty);
    // Only the backup's two logged days remain, not the one logged before.
    expect(await target.select(target.completions).get(), hasLength(2));
  });

  test('invalid files are rejected and change nothing', () async {
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await target.insertHabit(HabitsCompanion.insert(name: 'Keep', iconKey: 'x', colorValue: 1));

    for (final bad in [
      'not json at all',
      '[]',
      '{"app":"other","version":1}',
      '{"app":"ember","version":99}',
      '{"app":"ember","version":1,"habits":"nope"}',
      '{"app":"ember","version":1,"habits":[{"id":1}]}',
      '{"app":"ember","version":1,"habits":[],"completions":[{"id":1,"habitId":5,"day":"2026-01-01","amount":1}]}',
    ]) {
      await expectLater(restoreBackupJson(target, bad), throwsA(isA<BackupException>()), reason: bad);
    }
    final habits = await target.select(target.habits).get();
    expect(habits.single.name, 'Keep');
  });

  test('a backup without goal rows gets starting goals', () async {
    final json = await exportBackupJson(source);
    final stripped = json.replaceFirst(RegExp(r'"habitGoals": \[[\s\S]*\]\s*\}\s*$'), '"habitGoals": []\n}');
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await restoreBackupJson(target, stripped);
    expect(await target.select(target.habitGoals).get(), hasLength(2));
  });

  test('history CSV has a row per logged day with that day\'s goal', () async {
    final csv = await exportHistoryCsv(source);
    final lines = csv.trim().split('\n');
    expect(lines.first, 'habit,date,amount,unit,goal,done');
    expect(lines, hasLength(3));
    expect(lines[1], '"Run, ""fast""",${dayKey(addDays(today, -2))},2,times,2,yes');
    expect(lines[2], 'Study,${dayKey(addDays(today, -1))},900,seconds,1800,no');
  });
}
