import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/day.dart';
import '../core/reminder_plan.dart';
import '../core/timer.dart';
import '../data/database.dart';
import '../data/day_start.dart';
import '../data/providers.dart' show scheduleForHabit;

class HabitNotificationService {
  HabitNotificationService._();

  static final HabitNotificationService instance = HabitNotificationService._();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'habit_reminders';
  static const _channelName = 'Habit reminders';

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    final localZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localZone));
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: habitNotificationBackground,
    );
    _initialized = true;
  }

  // Reminders are a convenience. A failure here (a missing plugin, a denied
  // permission, an unknown time zone) must never stop a habit from being
  // saved, paused, archived or deleted, so every public call below catches and
  // logs its own errors instead of throwing into the caller.
  Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Ember reminders: $error');
    }
  }

  Future<bool> requestPermission() async {
    try {
      await initialize();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (error) {
      debugPrint('Ember reminders: $error');
      return false;
    }
  }

  /// Schedules every habit's reminders. [doneToday] are the habits already
  /// finished today, which get no reminder for the rest of the day.
  Future<void> syncAll(List<Habit> habits, {Set<int> doneToday = const {}}) async {
    for (final habit in habits) {
      await syncHabit(habit, doneToday: doneToday.contains(habit.id));
    }
  }

  Future<void> syncHabit(Habit habit, {bool doneToday = false}) =>
      _safely(() => _syncHabit(habit, doneToday));

  Future<void> _syncHabit(Habit habit, bool doneToday) async {
    await initialize();
    await _cancelHabit(habit.id);
    if (!habit.reminderEnabled || habit.archivedAt != null || habit.pausedAt != null) return;

    final plan = planReminders(
      now: DateTime.now(),
      schedule: scheduleForHabit(habit),
      startDate: habit.createdAt,
      hour: habit.reminderHour,
      minute: habit.reminderMinute,
      nudgeEnabled: habit.partialNudgeEnabled,
      nudgeHour: habit.partialNudgeHour,
      nudgeMinute: habit.partialNudgeMinute,
      doneToday: doneToday,
    );
    for (final reminder in plan) {
      await _schedule(habit: habit, reminder: reminder);
    }
  }

  Future<void> _schedule({required Habit habit, required PlannedReminder reminder}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Gentle reminders for the habits you choose.',
        importance: Importance.high,
        priority: Priority.high,
        actions: [AndroidNotificationAction('done', 'Done', showsUserInterface: false)],
      ),
    );
    final when = reminder.when;
    await _plugin.zonedSchedule(
      reminderNotificationId(habit.id, when, nudge: reminder.nudge),
      reminder.nudge ? 'A little Ember reminder' : habit.name,
      reminder.nudge
          ? 'A second reminder for ${habit.name}. Keep your momentum going.'
          : 'A small step today keeps your streak alive.',
      tz.TZDateTime(tz.local, when.year, when.month, when.day, when.hour, when.minute),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: habit.id.toString(),
    );
  }

  Future<void> cancelHabit(int habitId) => _safely(() => _cancelHabit(habitId));

  Future<void> _cancelHabit(int habitId) async {
    await initialize();
    // Older versions scheduled repeating reminders under these ids.
    for (var day = 0; day <= 7; day++) {
      await _plugin.cancel(_notificationId(habitId, day, false));
      await _plugin.cancel(_notificationId(habitId, day, true));
    }
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (isReminderIdOf(pending.id, habitId)) await _plugin.cancel(pending.id);
    }
  }

  /// Drops today's reminders for a habit that was just finished (for example
  /// from the widget or the notification's Done button, when the app is closed).
  Future<void> cancelToday(int habitId) => _safely(() async {
        await initialize();
        // Reminders are scheduled for calendar dates, so this is the real date.
        final today = startOfDay(DateTime.now());
        await _plugin.cancel(reminderNotificationId(habitId, today, nudge: false));
        await _plugin.cancel(reminderNotificationId(habitId, today, nudge: true));
      });

  static int _notificationId(int habitId, int weekday, bool nudge) =>
      habitId * 100 + (nudge ? 50 : 0) + weekday + 1;

  // ---- Timers -------------------------------------------------------------

  static const _timerChannelId = 'habit_timer';
  static const _timerChannelName = 'Habit timers';
  static const _timerPayloadPrefix = 'timer:';

  static int _timerNotificationId(int habitId) => 900000 + habitId;

  /// Shows (or refreshes) the ongoing notification for a habit's timer. While
  /// running the system draws a live clock, so the app does not need to wake up
  /// every second.
  Future<void> showTimer(Habit habit, TimerState timer, {int? secondsUntilGoal}) => _safely(() async {
        await initialize();
        final now = DateTime.now();
        final elapsed = timer.elapsedSeconds(now);
        final running = timer.isRunning;
        final startMs = now.millisecondsSinceEpoch - elapsed * 1000;
        await _plugin.show(
          _timerNotificationId(habit.id),
          habit.name,
          running ? 'Timer running' : 'Paused at ${formatClock(elapsed)}',
          NotificationDetails(
            android: AndroidNotificationDetails(
              _timerChannelId,
              _timerChannelName,
              channelDescription: 'Shows a timer that is running for a habit.',
              importance: Importance.low,
              priority: Priority.low,
              ongoing: true,
              autoCancel: false,
              onlyAlertOnce: true,
              showWhen: running,
              when: startMs,
              usesChronometer: running,
              category: AndroidNotificationCategory.stopwatch,
              actions: [
                AndroidNotificationAction(running ? 'timer_pause' : 'timer_resume', running ? 'Pause' : 'Resume', showsUserInterface: false),
                const AndroidNotificationAction('timer_save', 'Save', showsUserInterface: false),
              ],
            ),
          ),
          payload: '$_timerPayloadPrefix${habit.id}',
        );
        await _syncGoalAlert(habit, running ? secondsUntilGoal : null);
      });

  static int _goalAlertId(int habitId) => 910000 + habitId;

  /// Schedules a one-time "goal reached" alert, or cancels it when there is
  /// nothing to wait for (the timer is paused, saved or already past the goal).
  Future<void> _syncGoalAlert(Habit habit, int? secondsUntilGoal) async {
    final id = _goalAlertId(habit.id);
    await _plugin.cancel(id);
    if (secondsUntilGoal == null || secondsUntilGoal <= 0) return;
    await _plugin.zonedSchedule(
      id,
      '${habit.name}: goal reached',
      'Nice work. Open Ember to save your time.',
      tz.TZDateTime.now(tz.local).add(Duration(seconds: secondsUntilGoal)),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Gentle reminders for the habits you choose.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: '$_timerPayloadPrefix${habit.id}',
    );
  }

  Future<void> cancelTimer(int habitId) => _safely(() async {
        await initialize();
        await _plugin.cancel(_timerNotificationId(habitId));
        await _plugin.cancel(_goalAlertId(habitId));
      });

  static Future<void> _dispatch(NotificationResponse response) async {
    await loadDayStart();
    final action = response.actionId;
    final payload = response.payload ?? '';
    if (action == 'done') {
      await _markHabitDone(payload);
    } else if (payload.startsWith(_timerPayloadPrefix) && action != null && action.startsWith('timer_')) {
      await _timerAction(action, int.tryParse(payload.substring(_timerPayloadPrefix.length)));
    }
  }

  /// Handles Pause / Resume / Save pressed on the notification. This can run
  /// while the app is closed, so it talks to the database directly.
  static Future<void> _timerAction(String action, int? habitId) async {
    if (habitId == null) return;
    final db = AppDatabase();
    try {
      final now = DateTime.now();
      switch (action) {
        case 'timer_pause':
          await db.pauseTimer(habitId, now);
        case 'timer_resume':
          await db.startTimer(habitId, now);
        case 'timer_save':
          await db.finishTimer(habitId, now);
      }
      final timer = await db.getTimer(habitId);
      if (timer == null) {
        await instance.cancelTimer(habitId);
        return;
      }
      final habit = await (db.select(db.habits)..where((h) => h.id.equals(habitId))).getSingleOrNull();
      if (habit != null) {
        await instance.showTimer(
          habit,
          AppDatabase.stateOf(timer),
          secondsUntilGoal: await db.secondsUntilGoal(habitId, now),
        );
      }
    } catch (error) {
      debugPrint('Ember timer: $error');
    } finally {
      await db.close();
    }
  }

  static Future<void> _handleResponse(NotificationResponse response) => _dispatch(response);

  @pragma('vm:entry-point')
  static Future<void> habitNotificationBackground(NotificationResponse response) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await _dispatch(response);
  }

  static Future<void> _markHabitDone(String? payload) async {
    final habitId = int.tryParse(payload ?? '');
    if (habitId == null) return;
    final db = AppDatabase();
    try {
      final habit = await (db.select(db.habits)..where((row) => row.id.equals(habitId))).getSingleOrNull();
      if (habit == null) return;
      final target = habit.taskType == 2 ? habit.targetDurationSeconds : habit.dailyTarget;
      await db.setCompletion(habitId: habit.id, day: currentDayKey(), amount: target);
      await instance.cancelToday(habit.id);
    } finally {
      await db.close();
    }
  }
}
