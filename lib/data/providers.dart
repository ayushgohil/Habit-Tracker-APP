import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/day.dart';
import '../core/goals.dart';
import '../core/streak.dart';
import '../health/health_writer.dart';
import '../core/timer.dart';
import 'database.dart';
import 'day_start.dart';
import '../notifications/habit_notification_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
final todayProvider = StateProvider<DateTime>((ref) => currentDay());

/// Minutes after midnight when a new day begins. Changing it moves "today".
class DayStartController extends StateNotifier<int> {
  DayStartController(this._ref) : super(dayStartOffsetMinutes);
  final Ref _ref;

  Future<void> select(int minutes) async {
    final value = minutes.clamp(0, maxDayStartMinutes).toInt();
    dayStartOffsetMinutes = value;
    state = value;
    _ref.read(todayProvider.notifier).state = currentDay();
    await saveDayStart(value);
  }
}

final dayStartProvider = StateNotifierProvider<DayStartController, int>((ref) => DayStartController(ref));
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
    this.atRisk = false,
  });
  final Habit habit;
  final int countToday;
  final HabitStats stats;
  final Schedule schedule;

  /// What counts as done on the viewed day (the goal in force on that day).
  final int target;
  Streak get streak => stats.currentStreak;

  /// Not doing this today would end its streak (only set when viewing today).
  final bool atRisk;
  bool get isDone => habit.limitMode ? countToday <= target : countToday >= target;

  /// "750 / 2000 ml" while a counted habit is partly done, otherwise null.
  String? get progressText {
    if (habit.limitMode) return 'Used ${formatClock(countToday)} of ${formatClock(target)}';
    if (habit.taskType == HabitTaskType.timed.index || target <= 1 || countToday <= 0 || isDone) return null;
    final unit = habit.unitLabel.trim();
    return unit.isEmpty ? '$countToday / $target' : '$countToday / $target $unit';
  }
  double get progress => habit.limitMode ? (isDone ? 1.0 : 0.0) : target <= 0 ? 0 : (countToday / target).clamp(0.0, 1.0).toDouble();
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

/// The day a habit's numbers are worked out to: today, or its last day once it
/// has ended, so finishing a habit never counts as missing the days after it.
DateTime _throughDay(Habit habit, DateTime today) {
  final end = habit.endDate;
  if (end == null || !hasEndedBefore(end, today)) return today;
  return startOfDay(end);
}

HabitStats _statsFor(Habit habit, GoalTimeline timeline, Map<String, int> amounts, DateTime day) {
  final today = _throughDay(habit, day);
  return calculateHabitStats(
    // Periods are laid out with the current schedule. Each day is judged
    // against the goal that applied on that day.
    schedule: timeline.latest.schedule,
    doneDays: _doneDays(habit, timeline, amounts, today),
    createdAt: habit.createdAt,
    today: today,
    taskType: HabitTaskType.values[habit.taskType],
    twoDayRule: habit.twoDayRule,
    dayProgress: _progressByDay(habit, timeline, amounts, today),
  );
}

/// The days that count as done. A limit habit is done on every day it stayed
/// within its limit, logged or not; any other habit on the days it reached its goal.
Set<String> _doneDays(Habit habit, GoalTimeline timeline, Map<String, int> amounts, DateTime through) =>
    habit.limitMode
        ? timeline.underLimitDays(amounts, habit.createdAt, through)
        : timeline.doneDays(amounts);

Map<String, double> _progressByDay(Habit habit, GoalTimeline timeline, Map<String, int> amounts, DateTime through) =>
    habit.limitMode
        ? {for (final key in _doneDays(habit, timeline, amounts, through)) key: 1.0}
        : timeline.progressByDay(amounts);

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
      // A habit doesn't exist before it started or after it ended.
      if (hasStartedBy(habit.createdAt, day) && !hasEndedBefore(habit.endDate, day))
        _view(habit, timelineFor(habit, goals), byHabit[habit.id] ?? const {}, day, key),
  ]);
}

/// The habits as they look on [day], read straight from [db]. Used where no
/// providers exist, such as the home-screen widget's background tap.
Future<List<HabitView>> loadViewsOn(AppDatabase db, DateTime day) async {
  final habits = await db.activeHabitsNow();
  final completions = await db.select(db.completions).get();
  final goals = await db.select(db.habitGoals).get();
  return _viewsFor(
        AsyncValue.data(habits),
        AsyncValue.data(completions),
        AsyncValue.data(goals),
        day,
      ).valueOrNull ??
      const [];
}

/// Every active habit's history as of [day], read straight from [db].
Future<List<HabitHistory>> loadHistoriesOn(AppDatabase db, DateTime day) async {
  final habits = await db.activeHabitsNow();
  final completions = await db.select(db.completions).get();
  final goals = await db.select(db.habitGoals).get();
  final byHabit = <int, Map<String, int>>{};
  for (final item in completions) {
    (byHabit[item.habitId] ??= {})[item.day] = item.amount;
  }
  return [
    for (final habit in habits)
      if (hasStartedBy(habit.createdAt, day) && !hasEndedBefore(habit.endDate, day))
        buildHistory(habit, timelineFor(habit, goals), byHabit[habit.id] ?? const {}, day),
  ];
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
  ref.watch(dayStartProvider);
  return _viewsFor(
    ref.watch(habitsProvider),
    ref.watch(completionsProvider),
    ref.watch(goalsProvider),
    currentDay(),
  );
});

HabitView _view(Habit habit, GoalTimeline timeline, Map<String, int> amounts, DateTime day, String key) {
  final isToday = key == currentDayKey();
  return HabitView(
    atRisk: isToday &&
        !habit.limitMode &&
        streakAtRisk(
          schedule: timeline.latest.schedule,
          doneDays: _doneDays(habit, timeline, amounts, day),
          createdAt: habit.createdAt,
          today: day,
          taskType: HabitTaskType.values[habit.taskType],
          twoDayRule: habit.twoDayRule,
        ),
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
    required this.doneDays,
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

  /// Days that count as done (see [_doneDays]).
  final Set<String> doneDays;
  int get totalDone => doneDays.length;
}

HabitHistory buildHistory(Habit habit, GoalTimeline timeline, Map<String, int> amounts, DateTime today) {
  return HabitHistory(
    habit: habit,
    amounts: amounts,
    stats: _statsFor(habit, timeline, amounts, today),
    timeline: timeline,
    doneDays: _doneDays(habit, timeline, amounts, _throughDay(habit, today)),
  );
}

/// Live history for one habit (by id). Null while loading or if it is gone.
final habitHistoryProvider = Provider.family<HabitHistory?, int>((ref, id) {
  ref.watch(dayStartProvider);
  final today = currentDay();
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
  Future<void> setAmount(HabitView view, DateTime day, int amount) async {
    await _db.setCompletion(habitId: view.habit.id, day: dayKey(day), amount: amount);
    await mirrorToHealth(view.habit, view.countToday, amount, day);
  }
  /// Sets what was logged for a habit on any day (used by the calendar).
  Future<void> setDayAmount(int habitId, DateTime day, int amount) =>
      _db.setCompletion(habitId: habitId, day: dayKey(day), amount: amount);
  Future<void> tap(HabitView view, DateTime day) =>
      setAmount(view, day, view.isDone ? 0 : view.countToday + view.habit.stepSize);
  Future<void> setTimedProgress(HabitView view, DateTime day, int seconds) =>
      setAmount(view, day, seconds);
  Future<String?> loadNote(DateTime day) =>
      _db.getDayNote(day: dayKey(day));
  Future<void> saveNote(DateTime day, String note) =>
      _db.setDayNote(day: dayKey(day), note: note);
  Future<void> setNotePinned(String day, bool pinned) => _db.setNotePinned(day: day, pinned: pinned);
  Future<int> add({
    required String name, required String iconKey, required int colorValue,
    required Schedule schedule, required int dailyTarget, required int sortOrder,
    HabitTaskType taskType = HabitTaskType.normal, bool twoDayRule = false,
    int targetDurationSeconds = 1800,
    bool reminderEnabled = false, int reminderHour = 20, int reminderMinute = 0,
    bool partialNudgeEnabled = false, int partialNudgeHour = 21, int partialNudgeMinute = 0,
    DateTime? startDate,
    int healthMetric = 0,
    String unitLabel = '',
    int stepSize = 1,
    String extraReminders = '',
    int sessionSeconds = 0,
    bool limitMode = false,
    String linkUrl = '',
    bool writeToHealth = false,
    DateTime? endDate,
  }) => _db.insertHabit(HabitsCompanion.insert(
    name: name, iconKey: iconKey, colorValue: colorValue, healthMetric: Value(healthMetric),
    unitLabel: Value(unitLabel), stepSize: Value(stepSize), extraReminders: Value(extraReminders), sessionSeconds: Value(sessionSeconds), limitMode: Value(limitMode), linkUrl: Value(linkUrl), writeToHealth: Value(writeToHealth),
    createdAt: startDate == null ? const Value.absent() : Value(startDate),
    endDate: Value(endDate),
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
    String unitLabel = '',
    int stepSize = 1,
    String extraReminders = '',
    int sessionSeconds = 0,
    bool limitMode = false,
    String linkUrl = '',
    bool writeToHealth = false,
    DateTime? endDate,
  }) async {
    final before = await (_db.select(_db.habits)..where((h) => h.id.equals(id))).getSingleOrNull();
    await _db.updateHabit(id, HabitsCompanion(
    name: Value(name), iconKey: Value(iconKey), colorValue: Value(colorValue), healthMetric: Value(healthMetric),
    unitLabel: Value(unitLabel), stepSize: Value(stepSize), extraReminders: Value(extraReminders), sessionSeconds: Value(sessionSeconds), limitMode: Value(limitMode), linkUrl: Value(linkUrl), writeToHealth: Value(writeToHealth),
    createdAt: startDate == null ? const Value.absent() : Value(startDate),
    endDate: Value(endDate),
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
      await _db.recordGoalFrom(id, currentDayKey());
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
        alerts: await _db.timerAlerts(habitId, DateTime.now()),
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
/// Every day note, newest first.
final allNotesProvider = StreamProvider<List<DayNote>>((ref) => ref.watch(databaseProvider).watchNotes());

final habitActionsProvider = Provider<HabitActions>((ref) => HabitActions(ref.watch(databaseProvider)));
