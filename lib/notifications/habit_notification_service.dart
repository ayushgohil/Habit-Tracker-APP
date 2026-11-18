import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/day.dart';
import '../core/timer.dart';
import '../data/database.dart';

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

  Future<void> syncAll(List<Habit> habits) async {
    for (final habit in habits) {
      await syncHabit(habit);
    }
  }

  Future<void> syncHabit(Habit habit) => _safely(() => _syncHabit(habit));

  Future<void> _syncHabit(Habit habit) async {
    await initialize();
    await _cancelHabit(habit.id);
    if (!habit.reminderEnabled || habit.archivedAt != null || habit.pausedAt != null) return;

    final weekdays = habit.scheduleType == 1
        ? [for (var day = 1; day <= 7; day++) if ((habit.weekdayMask & (1 << (day - 1))) != 0) day]
        : <int>[];

    if (weekdays.isEmpty) {
      await _schedule(id: _notificationId(habit.id, 0, false), habit: habit,
          hour: habit.reminderHour, minute: habit.reminderMinute, weekday: null, isNudge: false);
      if (habit.partialNudgeEnabled) {
        await _schedule(id: _notificationId(habit.id, 0, true), habit: habit,
            hour: habit.partialNudgeHour, minute: habit.partialNudgeMinute, weekday: null, isNudge: true);
      }
    } else {
      for (final weekday in weekdays) {
        await _schedule(id: _notificationId(habit.id, weekday, false), habit: habit,
            hour: habit.reminderHour, minute: habit.reminderMinute, weekday: weekday, isNudge: false);
        if (habit.partialNudgeEnabled) {
          await _schedule(id: _notificationId(habit.id, weekday, true), habit: habit,
              hour: habit.partialNudgeHour, minute: habit.partialNudgeMinute, weekday: weekday, isNudge: true);
        }
      }
    }
  }

  Future<void> _schedule({
    required int id,
    required Habit habit,
    required int hour,
    required int minute,
    required int? weekday,
    required bool isNudge,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (weekday == null) {
      if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));
    } else {
      var daysAhead = (weekday - now.weekday + 7) % 7;
      if (daysAhead == 0 && !scheduled.isAfter(now)) daysAhead = 7;
      scheduled = scheduled.add(Duration(days: daysAhead));
    }

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

    await _plugin.zonedSchedule(
      id,
      isNudge ? 'A little Ember reminder' : habit.name,
      isNudge
          ? 'A second reminder for ${habit.name}. Keep your momentum going.'
          : 'A small step today keeps your streak alive.',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: weekday == null
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
      payload: habit.id.toString(),
    );
  }

  Future<void> cancelHabit(int habitId) => _safely(() => _cancelHabit(habitId));

  Future<void> _cancelHabit(int habitId) async {
    await initialize();
    for (var day = 0; day <= 7; day++) {
      await _plugin.cancel(_notificationId(habitId, day, false));
      await _plugin.cancel(_notificationId(habitId, day, true));
    }
  }

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
  Future<void> showTimer(Habit habit, TimerState timer) => _safely(() async {
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
      });

  Future<void> cancelTimer(int habitId) => _safely(() async {
        await initialize();
        await _plugin.cancel(_timerNotificationId(habitId));
      });

  static Future<void> _dispatch(NotificationResponse response) async {
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
      if (habit != null) await instance.showTimer(habit, AppDatabase.stateOf(timer));
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
      await db.setCompletion(habitId: habit.id, day: dayKey(DateTime.now()), amount: target);
    } finally {
      await db.close();
    }
  }
}
