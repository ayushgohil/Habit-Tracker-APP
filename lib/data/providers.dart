import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/day.dart';
import '../core/streak.dart';
import '../core/timer.dart';
import 'database.dart';
import '../notifications/habit_notification_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
final todayProvider = StateProvider<DateTime>((ref) => startOfDay(DateTime.now()));
final habitsProvider = StreamProvider<List<Habit>>((ref) => ref.watch(databaseProvider).watchActiveHabits());
final pausedHabitsProvider = StreamProvider<List<Habit>>((ref) => ref.watch(databaseProvider).watchPausedHabits());
final archivedHabitsProvider = StreamProvider<List<Habit>>((ref) => ref.watch(databaseProvider).watchArchivedHabits());
final allHabitsProvider = StreamProvider<List<Habit>>((ref) => ref.watch(databaseProvider).watchAllHabits());
final timersProvider = StreamProvider<List<ActiveTimer>>((ref) => ref.watch(databaseProvider).watchTimers());
final completionsProvider =StreamProvider<List<Completion>>((ref) => ref.watch(databaseProvider).watchAllCompletions());

class HabitView {
  const HabitView({required this.habit, required this.countToday, required this.stats, required this.schedule});
  final Habit habit;
  final int countToday;
  final HabitStats stats;
  final Schedule schedule;
  Streak get streak => stats.currentStreak;
  int get target => habit.taskType == HabitTaskType.timed.index ? habit.targetDurationSeconds : habit.dailyTarget;
  bool get isDone => countToday >= target;
  double get progress => target <= 0 ? 0 : (countToday / target).clamp(0.0, 1.0).toDouble();
}

final habitViewsProvider = Provider<AsyncValue<List<HabitView>>>((ref) {
  final selectedDay = ref.watch(todayProvider);
  final h = ref.watch(habitsProvider);
  final c = ref.watch(completionsProvider);
  final error = h.error ?? c.error;
  if (error != null) return AsyncValue.error(error, StackTrace.current);
  final habits = h.valueOrNull;
  final completions = c.valueOrNull;
  if (habits == null || completions == null) return const AsyncValue.loading();
  final byHabit = <int, Map<String, int>>{};
  for (final item in completions) {
    (byHabit[item.habitId] ??= {})[item.day] = item.amount;
  }
  final selectedKey = dayKey(selectedDay);
  return AsyncValue.data([
    for (final habit in habits)
      // A habit doesn't exist on days before it started.
      if (hasStartedBy(habit.createdAt, selectedDay))
        _view(habit, byHabit[habit.id] ?? const {}, selectedDay, selectedKey),
  ]);
});

/// What counts as "done" for a habit on one day.
int targetForHabit(Habit habit) =>
    habit.taskType == HabitTaskType.timed.index ? habit.targetDurationSeconds : habit.dailyTarget;

Schedule scheduleForHabit(Habit habit) => Schedule(
      type: ScheduleType.values[habit.scheduleType],
      weekdayMask: habit.weekdayMask,
      timesPerWeek: habit.timesPerWeek,
      intervalDays: habit.intervalDays,
      periodTarget: habit.periodTarget,
      anchorDate: habit.createdAt,
    );

/// Everything the stats screen needs about one habit, as of [today].
class HabitHistory {
  const HabitHistory({
    required this.habit,
    required this.amounts,
    required this.stats,
    required this.schedule,
    required this.target,
  });
  final Habit habit;
  final Map<String, int> amounts;
  final HabitStats stats;
  final Schedule schedule;
  final int target;

  Set<String> get doneDays => {for (final e in amounts.entries) if (e.value >= target) e.key};
  int get totalDone => doneDays.length;
}

HabitHistory buildHistory(Habit habit, Map<String, int> amounts, DateTime today) {
  final target = targetForHabit(habit);
  final schedule = scheduleForHabit(habit);
  final doneDays = <String>{for (final e in amounts.entries) if (e.value >= target) e.key};
  final stats = calculateHabitStats(
    schedule: schedule,
    doneDays: doneDays,
    createdAt: habit.createdAt,
    today: today,
    taskType: HabitTaskType.values[habit.taskType],
    twoDayRule: habit.twoDayRule,
  );
  return HabitHistory(habit: habit, amounts: amounts, stats: stats, schedule: schedule, target: target);
}

/// Live history for one habit (by id). Null while loading or if it is gone.
final habitHistoryProvider = Provider.family<HabitHistory?, int>((ref, id) {
  final today = startOfDay(DateTime.now());
  final habits = ref.watch(allHabitsProvider).valueOrNull;
  final completions = ref.watch(completionsProvider).valueOrNull;
  if (habits == null || completions == null) return null;
  final matches = habits.where((h) => h.id == id);
  if (matches.isEmpty) return null;
  final amounts = <String, int>{
    for (final c in completions) if (c.habitId == id) c.day: c.amount,
  };
  return buildHistory(matches.first, amounts, today);
});

HabitView _view(Habit habit, Map<String, int> amounts, DateTime day, String key) {
  final target = targetForHabit(habit);
  final schedule = scheduleForHabit(habit);
  final doneDays = <String>{for (final e in amounts.entries) if (e.value >= target) e.key};
  final stats = calculateHabitStats(
    schedule: schedule,
    doneDays: doneDays,
    createdAt: habit.createdAt,
    today: day,
    taskType: HabitTaskType.values[habit.taskType],
    twoDayRule: habit.twoDayRule,
  );
  return HabitView(habit: habit, countToday: amounts[key] ?? 0, stats: stats, schedule: schedule);
}

class HabitActions {
  HabitActions(this._db);
  final AppDatabase _db;
  Future<void> setAmount(HabitView view, DateTime day, int amount) =>
      _db.setCompletion(habitId: view.habit.id, day: dayKey(day), amount: amount);
  /// Sets what was logged for a habit on any day (used by the calendar).
  Future<void> setDayAmount(int habitId, DateTime day, int amount) =>
      _db.setCompletion(habitId: habitId, day: dayKey(day), amount: amount);
  Future<void> tap(HabitView view, DateTime day) =>
      setAmount(view, day, view.isDone ? 0 : view.countToday + 1);
  Future<void> setTimedProgress(HabitView view, DateTime day, int seconds) =>
      setAmount(view, day, seconds);
  Future<String?> loadNote(DateTime day) =>
      _db.getDayNote(day: dayKey(day));
  Future<void> saveNote(DateTime day, String note) =>
      _db.setDayNote(day: dayKey(day), note: note);
  Future<int> add({
    required String name, required String iconKey, required int colorValue,
    required Schedule schedule, required int dailyTarget, required int sortOrder,
    HabitTaskType taskType = HabitTaskType.normal, bool twoDayRule = false,
    int targetDurationSeconds = 1800,
    bool reminderEnabled = false, int reminderHour = 20, int reminderMinute = 0,
    bool partialNudgeEnabled = false, int partialNudgeHour = 21, int partialNudgeMinute = 0,
    DateTime? startDate,
  }) => _db.insertHabit(HabitsCompanion.insert(
    name: name, iconKey: iconKey, colorValue: colorValue,
    createdAt: startDate == null ? const Value.absent() : Value(startDate),
    scheduleType: Value(schedule.type.index), weekdayMask: Value(schedule.weekdayMask),
    timesPerWeek: Value(schedule.timesPerWeek), dailyTarget: Value(dailyTarget),
    sortOrder: Value(sortOrder), taskType: Value(taskType.index),
    twoDayRule: Value(twoDayRule), intervalDays: Value(schedule.intervalDays),
    periodTarget: Value(schedule.periodTarget), targetDurationSeconds: Value(targetDurationSeconds),
    reminderEnabled: Value(reminderEnabled), reminderHour: Value(reminderHour), reminderMinute: Value(reminderMinute),
    partialNudgeEnabled: Value(partialNudgeEnabled), partialNudgeHour: Value(partialNudgeHour), partialNudgeMinute: Value(partialNudgeMinute),
  ));
  Future<void> edit({
    required int id, required String name, required String iconKey, required int colorValue,
    required Schedule schedule, required int dailyTarget, required HabitTaskType taskType,
    required bool twoDayRule, required int targetDurationSeconds,
    required bool reminderEnabled, required int reminderHour, required int reminderMinute,
    required bool partialNudgeEnabled, required int partialNudgeHour, required int partialNudgeMinute,
    DateTime? startDate,
  }) => _db.updateHabit(id, HabitsCompanion(
    name: Value(name), iconKey: Value(iconKey), colorValue: Value(colorValue),
    createdAt: startDate == null ? const Value.absent() : Value(startDate),
    scheduleType: Value(schedule.type.index), weekdayMask: Value(schedule.weekdayMask),
    timesPerWeek: Value(schedule.timesPerWeek), intervalDays: Value(schedule.intervalDays),
    periodTarget: Value(schedule.periodTarget), dailyTarget: Value(dailyTarget),
    taskType: Value(taskType.index), twoDayRule: Value(twoDayRule),
    targetDurationSeconds: Value(targetDurationSeconds),
    reminderEnabled: Value(reminderEnabled), reminderHour: Value(reminderHour), reminderMinute: Value(reminderMinute),
    partialNudgeEnabled: Value(partialNudgeEnabled), partialNudgeHour: Value(partialNudgeHour), partialNudgeMinute: Value(partialNudgeMinute),
  ));
  Future<void> _syncReminder(int id) async {
    final habit = await (_db.select(_db.habits)..where((h) => h.id.equals(id))).getSingleOrNull();
    if (habit == null) {
      await HabitNotificationService.instance.cancelHabit(id);
    } else {
      await HabitNotificationService.instance.syncHabit(habit);
    }
  }

  Future<void> _syncTimerNotification(int habitId) async {
    final timer = await _db.getTimer(habitId);
    final habit = await (_db.select(_db.habits)..where((h) => h.id.equals(habitId))).getSingleOrNull();
    if (timer == null || habit == null) {
      await HabitNotificationService.instance.cancelTimer(habitId);
    } else {
      await HabitNotificationService.instance.showTimer(habit, AppDatabase.stateOf(timer));
    }
  }

  /// Starts a timer, or resumes a paused one.
  Future<void> startTimer(int habitId) async {
    await _db.startTimer(habitId, DateTime.now());
    await _syncTimerNotification(habitId);
  }

  Future<void> pauseTimer(int habitId) async {
    await _db.pauseTimer(habitId, DateTime.now());
    await _syncTimerNotification(habitId);
  }

  /// Saves the timer's time to its day. Returns the seconds saved.
  Future<int> finishTimer(int habitId) async {
    final seconds = await _db.finishTimer(habitId, DateTime.now());
    await _syncTimerNotification(habitId);
    return seconds;
  }

  Future<void> discardTimer(int habitId) async {
    await _db.discardTimer(habitId);
    await _syncTimerNotification(habitId);
  }

  Future<void> archive(int id) async {
    await _db.archiveHabit(id);
    await _syncReminder(id);
  }

  Future<void> restore(int id) async {
    await _db.restoreHabit(id);
    await _syncReminder(id);
  }

  Future<void> pause(int id) async {
    await _db.pauseHabit(id);
    await _syncReminder(id);
  }

  Future<void> resume(int id) async {
    await _db.resumeHabit(id);
    await _syncReminder(id);
  }
  Future<void> reorder(List<int> ids) => _db.reorderHabits(ids);
  Future<void> delete(int id) async {
    await _db.deleteHabit(id);
    await HabitNotificationService.instance.cancelHabit(id);
    await HabitNotificationService.instance.cancelTimer(id);
  }
}
final habitActionsProvider = Provider<HabitActions>((ref) => HabitActions(ref.watch(databaseProvider)));
