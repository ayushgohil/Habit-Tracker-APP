import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/day.dart';
import '../core/goals.dart';
import '../core/streak.dart';
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
final goalsProvider = StreamProvider<List<HabitGoal>>((ref) => ref.watch(databaseProvider).watchGoals());
final timersProvider = StreamProvider<List<ActiveTimer>>((ref) => ref.watch(databaseProvider).watchTimers());
final completionsProvider =StreamProvider<List<Completion>>((ref) => ref.watch(databaseProvider).watchAllCompletions());

class HabitView {
  const HabitView({
    required this.habit,
    required this.countToday,
    required this.stats,
    required this.schedule,
    required this.target,
  });
  final Habit habit;
  final int countToday;
  final HabitStats stats;
  final Schedule schedule;

  /// What counts as done on the viewed day (the goal in force on that day).
  final int target;
  Streak get streak => stats.currentStreak;
  bool get isDone => countToday >= target;
  double get progress => target <= 0 ? 0 : (countToday / target).clamp(0.0, 1.0).toDouble();
}

/// What counts as "done" for a habit right now, from the habit's own columns.
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

/// The goals a habit has had over time. A habit with no recorded goals (which
/// should not happen) falls back to its current settings for every day.
GoalTimeline timelineFor(Habit habit, Iterable<HabitGoal> goals) {
  final mine = goals.where((g) => g.habitId == habit.id).toList();
  if (mine.isEmpty) {
    return GoalTimeline.single(target: targetForHabit(habit), schedule: scheduleForHabit(habit));
  }
  return GoalTimeline([
    for (final g in mine)
      GoalVersion(
        from: g.effectiveFrom,
        target: g.target,
        schedule: Schedule(
          type: ScheduleType.values[g.scheduleType],
          weekdayMask: g.weekdayMask,
          timesPerWeek: g.timesPerWeek,
          intervalDays: g.intervalDays,
          periodTarget: g.periodTarget,
          anchorDate: habit.createdAt,
        ),
      ),
  ]);
}

HabitStats _statsFor(Habit habit, GoalTimeline timeline, Map<String, int> amounts, DateTime today) {
  return calculateHabitStats(
    // Periods are laid out with the current schedule. Each day is judged
    // against the goal that applied on that day.
    schedule: timeline.latest.schedule,
    doneDays: timeline.doneDays(amounts),
    createdAt: habit.createdAt,
    today: today,
    taskType: HabitTaskType.values[habit.taskType],
    twoDayRule: habit.twoDayRule,
    dayProgress: timeline.progressByDay(amounts),
  );
}

AsyncValue<List<HabitView>> _viewsFor(
  AsyncValue<List<Habit>> h,
  AsyncValue<List<Completion>> c,
  AsyncValue<List<HabitGoal>> g,
  DateTime day,
) {
  final error = h.error ?? c.error ?? g.error;
  if (error != null) return AsyncValue.error(error, StackTrace.current);
  final habits = h.valueOrNull;
  final completions = c.valueOrNull;
  final goals = g.valueOrNull;
  if (habits == null || completions == null || goals == null) return const AsyncValue.loading();
  final byHabit = <int, Map<String, int>>{};
  for (final item in completions) {
    (byHabit[item.habitId] ??= {})[item.day] = item.amount;
  }
  final key = dayKey(day);
  return AsyncValue.data([
    for (final habit in habits)
      // A habit doesn't exist on days before it started.
      if (hasStartedBy(habit.createdAt, day))
        _view(habit, timelineFor(habit, goals), byHabit[habit.id] ?? const {}, day, key),
  ]);
}

/// The habits as they look on the day being viewed on Home.
final habitViewsProvider = Provider<AsyncValue<List<HabitView>>>((ref) {
  return _viewsFor(
    ref.watch(habitsProvider),
    ref.watch(completionsProvider),
    ref.watch(goalsProvider),
    ref.watch(todayProvider),
  );
});

/// The habits as they look on the real current day, whatever day Home is
/// showing. Feeds the home-screen widget and the launcher shortcuts.
final liveTodayViewsProvider = Provider<AsyncValue<List<HabitView>>>((ref) {
  return _viewsFor(
    ref.watch(habitsProvider),
    ref.watch(completionsProvider),
    ref.watch(goalsProvider),
    startOfDay(DateTime.now()),
  );
});

HabitView _view(Habit habit, GoalTimeline timeline, Map<String, int> amounts, DateTime day, String key) {
  return HabitView(
    habit: habit,
    countToday: amounts[key] ?? 0,
    stats: _statsFor(habit, timeline, amounts, day),
    schedule: timeline.scheduleOn(day),
    target: timeline.targetOn(day),
  );
}

/// Everything the stats screen needs about one habit, as of today.
class HabitHistory {
  const HabitHistory({
    required this.habit,
    required this.amounts,
    required this.stats,
    required this.timeline,
  });
  final Habit habit;
  final Map<String, int> amounts;
  final HabitStats stats;
  final GoalTimeline timeline;

  /// The goal now.
  Schedule get schedule => timeline.latest.schedule;
  int get target => timeline.latest.target;
  int targetOn(DateTime day) => timeline.targetOn(day);
  Schedule scheduleOn(DateTime day) => timeline.scheduleOn(day);

  Set<String> get doneDays => timeline.doneDays(amounts);
  int get totalDone => doneDays.length;
}

HabitHistory buildHistory(Habit habit, GoalTimeline timeline, Map<String, int> amounts, DateTime today) {
  return HabitHistory(
    habit: habit,
    amounts: amounts,
    stats: _statsFor(habit, timeline, amounts, today),
    timeline: timeline,
  );
}

/// Live history for one habit (by id). Null while loading or if it is gone.
final habitHistoryProvider = Provider.family<HabitHistory?, int>((ref, id) {
  final today = startOfDay(DateTime.now());
  final habits = ref.watch(allHabitsProvider).valueOrNull;
  final completions = ref.watch(completionsProvider).valueOrNull;
  final goals = ref.watch(goalsProvider).valueOrNull;
  if (habits == null || completions == null || goals == null) return null;
  final matches = habits.where((h) => h.id == id);
  if (matches.isEmpty) return null;
  final amounts = <String, int>{
    for (final c in completions) if (c.habitId == id) c.day: c.amount,
  };
  return buildHistory(matches.first, timelineFor(matches.first, goals), amounts, today);
});

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
    int healthMetric = 0,
  }) => _db.insertHabit(HabitsCompanion.insert(
    name: name, iconKey: iconKey, colorValue: colorValue, healthMetric: Value(healthMetric),
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
    bool applyToWholeHistory = false,
    int healthMetric = 0,
  }) async {
    final before = await (_db.select(_db.habits)..where((h) => h.id.equals(id))).getSingleOrNull();
    await _db.updateHabit(id, HabitsCompanion(
    name: Value(name), iconKey: Value(iconKey), colorValue: Value(colorValue), healthMetric: Value(healthMetric),
    createdAt: startDate == null ? const Value.absent() : Value(startDate),
    scheduleType: Value(schedule.type.index), weekdayMask: Value(schedule.weekdayMask),
    timesPerWeek: Value(schedule.timesPerWeek), intervalDays: Value(schedule.intervalDays),
    periodTarget: Value(schedule.periodTarget), dailyTarget: Value(dailyTarget),
    taskType: Value(taskType.index), twoDayRule: Value(twoDayRule),
    targetDurationSeconds: Value(targetDurationSeconds),
    reminderEnabled: Value(reminderEnabled), reminderHour: Value(reminderHour), reminderMinute: Value(reminderMinute),
    partialNudgeEnabled: Value(partialNudgeEnabled), partialNudgeHour: Value(partialNudgeHour), partialNudgeMinute: Value(partialNudgeMinute),
    ));
    if (before == null) return;
    final goalChanged = before.taskType != taskType.index ||
        targetForHabit(before) != (taskType == HabitTaskType.timed ? targetDurationSeconds : dailyTarget) ||
        before.scheduleType != schedule.type.index ||
        before.weekdayMask != schedule.weekdayMask ||
        before.timesPerWeek != schedule.timesPerWeek ||
        before.intervalDays != schedule.intervalDays ||
        before.periodTarget != schedule.periodTarget;
    if (!goalChanged) return;
    if (applyToWholeHistory) {
      await _db.collapseGoals(id);
    } else {
      // Past days keep the goal they had; the new one starts today.
      await _db.recordGoalFrom(id, dayKey(DateTime.now()));
    }
  }

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
      await HabitNotificationService.instance.showTimer(
        habit,
        AppDatabase.stateOf(timer),
        secondsUntilGoal: await _db.secondsUntilGoal(habitId, DateTime.now()),
      );
    }
  }

  /// Saves what a running or paused timer has counted and removes it. Used
  /// when a habit is archived or paused, so no time is lost.
  Future<void> _endTimer(int habitId) async {
    if (await _db.getTimer(habitId) == null) return;
    await _db.finishTimer(habitId, DateTime.now());
    await _syncTimerNotification(habitId);
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
    await _endTimer(id);
    await _db.archiveHabit(id);
    await _syncReminder(id);
  }

  Future<void> restore(int id) async {
    await _db.restoreHabit(id);
    await _syncReminder(id);
  }

  Future<void> pause(int id) async {
    await _endTimer(id);
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
