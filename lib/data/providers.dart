import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/day.dart';
import '../core/streak.dart';
import 'database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The day the home screen is showing. Rolled over by `EmberApp` on resume.
final todayProvider =
    StateProvider<DateTime>((ref) => startOfDay(DateTime.now()));

final habitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(databaseProvider).watchActiveHabits(),
);

final completionsProvider = StreamProvider<List<Completion>>(
  (ref) => ref.watch(databaseProvider).watchAllCompletions(),
);

/// A habit together with what the home screen needs to draw it.
class HabitView {
  const HabitView({
    required this.habit,
    required this.countToday,
    required this.streak,
    required this.schedule,
  });

  final Habit habit;
  final int countToday;
  final Streak streak;
  final Schedule schedule;

  bool get isDone => countToday >= habit.dailyTarget;

  double get progress {
    if (habit.dailyTarget <= 0) return 0;
    return (countToday / habit.dailyTarget).clamp(0.0, 1.0).toDouble();
  }
}

final habitViewsProvider = Provider<AsyncValue<List<HabitView>>>((ref) {
  final today = ref.watch(todayProvider);
  final habitsAsync = ref.watch(habitsProvider);
  final completionsAsync = ref.watch(completionsProvider);

  final error = habitsAsync.error ?? completionsAsync.error;
  if (error != null) return AsyncValue.error(error, StackTrace.current);

  final habits = habitsAsync.valueOrNull;
  final completions = completionsAsync.valueOrNull;
  if (habits == null || completions == null) return const AsyncValue.loading();

  final amountsByHabit = <int, Map<String, int>>{};
  for (final c in completions) {
    (amountsByHabit[c.habitId] ??= {})[c.day] = c.amount;
  }

  final todayKey = dayKey(today);
  return AsyncValue.data([
    for (final h in habits)
      _buildView(h, amountsByHabit[h.id] ?? const {}, today, todayKey),
  ]);
});

HabitView _buildView(
  Habit h,
  Map<String, int> amounts,
  DateTime today,
  String todayKey,
) {
  final doneDays = <String>{
    for (final e in amounts.entries)
      if (e.value >= h.dailyTarget) e.key,
  };
  final schedule = Schedule(
    type: ScheduleType.values[h.scheduleType],
    weekdayMask: h.weekdayMask,
    timesPerWeek: h.timesPerWeek,
  );
  return HabitView(
    habit: h,
    countToday: amounts[todayKey] ?? 0,
    streak: computeStreak(schedule: schedule, doneDays: doneDays, today: today),
    schedule: schedule,
  );
}

/// Everything the UI can do to habits.
class HabitActions {
  HabitActions(this._db);

  final AppDatabase _db;

  /// Adds one step toward today's target; tapping a finished habit resets it.
  Future<void> tap(HabitView view, DateTime day) {
    final target = view.habit.dailyTarget;
    final next = view.countToday >= target ? 0 : view.countToday + 1;
    return _db.setCompletion(
      habitId: view.habit.id,
      day: dayKey(day),
      amount: next,
    );
  }

  Future<int> add({
    required String name,
    required String iconKey,
    required int colorValue,
    required Schedule schedule,
    required int dailyTarget,
    required int sortOrder,
  }) {
    return _db.insertHabit(
      HabitsCompanion.insert(
        name: name,
        iconKey: iconKey,
        colorValue: colorValue,
        scheduleType: Value(schedule.type.index),
        weekdayMask: Value(schedule.weekdayMask),
        timesPerWeek: Value(schedule.timesPerWeek),
        dailyTarget: Value(dailyTarget),
        sortOrder: Value(sortOrder),
      ),
    );
  }

  Future<void> archive(int id) => _db.archiveHabit(id);

  Future<void> delete(int id) => _db.deleteHabit(id);
}

final habitActionsProvider = Provider<HabitActions>(
  (ref) => HabitActions(ref.watch(databaseProvider)),
);
