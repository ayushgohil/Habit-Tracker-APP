import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/streak.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late HabitActions actions;
  final today = startOfDay(DateTime.now());

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    actions = HabitActions(db);
  });
  tearDown(() => db.close());

  Future<int> timedHabit() => db.insertHabit(
        HabitsCompanion.insert(
          name: 'Study',
          iconKey: 'book',
          colorValue: 0xFFFF6B2C,
          createdAt: Value(addDays(today, -10)),
          taskType: Value(HabitTaskType.timed.index),
          targetDurationSeconds: const Value(1800),
        ),
      );

  Future<void> editTo(int id, int seconds, {bool whole = false}) async {
    final habit = await (db.select(db.habits)..where((h) => h.id.equals(id))).getSingle();
    await actions.edit(
      id: id,
      name: habit.name,
      iconKey: habit.iconKey,
      colorValue: habit.colorValue,
      schedule: scheduleForHabit(habit),
      dailyTarget: habit.dailyTarget,
      taskType: HabitTaskType.timed,
      twoDayRule: habit.twoDayRule,
      targetDurationSeconds: seconds,
      reminderEnabled: false,
      reminderHour: 20,
      reminderMinute: 0,
      partialNudgeEnabled: false,
      partialNudgeHour: 21,
      partialNudgeMinute: 0,
      applyToWholeHistory: whole,
    );
  }

  Future<HabitHistory> historyOf(int id) async {
    final habit = await (db.select(db.habits)..where((h) => h.id.equals(id))).getSingle();
    final goals = await db.select(db.habitGoals).get();
    final completions = await db.select(db.completions).get();
    return buildHistory(
      habit,
      timelineFor(habit, goals),
      {for (final c in completions) c.day: c.amount},
      today,
    );
  }

  test('a new habit gets one starting goal', () async {
    final id = await timedHabit();
    final goals = await db.select(db.habitGoals).get();
    expect(goals, hasLength(1));
    expect(goals.single.habitId, id);
    expect(goals.single.target, 1800);
    expect(goals.single.effectiveFrom, dayKey(addDays(today, -10)));
  });

  test('raising the goal from today keeps past days done and the streak intact', () async {
    final id = await timedHabit();
    for (var i = 9; i >= 1; i--) {
      await db.setCompletion(habitId: id, day: dayKey(addDays(today, -i)), amount: 1800);
    }
    await editTo(id, 3600);

    final history = await historyOf(id);
    expect(history.timeline.versions, hasLength(2));
    expect(history.targetOn(addDays(today, -5)), 1800);
    expect(history.targetOn(today), 3600);
    expect(history.doneDays, hasLength(9));
    expect(history.stats.currentStreak.length, 9);

    // 30 minutes today is only half of the new goal.
    await db.setCompletion(habitId: id, day: dayKey(today), amount: 1800);
    final later = await historyOf(id);
    expect(later.doneDays, hasLength(9));
    expect(later.amounts[dayKey(today)], 1800);
    expect(later.stats.currentStreak.length, 9);
  });

  test('applying to all past days judges history by the new goal', () async {
    final id = await timedHabit();
    for (var i = 5; i >= 1; i--) {
      await db.setCompletion(habitId: id, day: dayKey(addDays(today, -i)), amount: 1800);
    }
    await editTo(id, 3600);
    await editTo(id, 7200, whole: true);

    final history = await historyOf(id);
    expect(history.timeline.versions, hasLength(1));
    expect(history.targetOn(addDays(today, -5)), 7200);
    expect(history.doneDays, isEmpty);
  });

  test('changing the goal twice on the same day keeps only the last one', () async {
    final id = await timedHabit();
    await editTo(id, 2400);
    await editTo(id, 3000);
    final goals = await db.select(db.habitGoals).get();
    expect(goals, hasLength(2));
    final history = await historyOf(id);
    expect(history.targetOn(today), 3000);
    expect(history.targetOn(addDays(today, -1)), 1800);
  });

  test('saving without changing the goal adds no entry', () async {
    final id = await timedHabit();
    await editTo(id, 1800);
    expect(await db.select(db.habitGoals).get(), hasLength(1));
  });

  test('deleting a habit removes its goals', () async {
    final id = await timedHabit();
    await editTo(id, 3600);
    await db.deleteHabit(id);
    expect(await db.select(db.habitGoals).get(), isEmpty);
  });
}
