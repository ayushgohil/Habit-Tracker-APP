import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/day.dart';
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

  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<void> syncAll(List<Habit> habits) async {
    await initialize();
    for (final habit in habits) {
      await syncHabit(habit);
    }
  }

  Future<void> syncHabit(Habit habit) async {
    await initialize();
    await cancelHabit(habit.id);
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

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Gentle reminders for the habits you choose.',
        importance: Importance.high,
        priority: Priority.high,
        actions: const [AndroidNotificationAction('done', 'Done', showsUserInterface: false)],
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

  Future<void> cancelHabit(int habitId) async {
    await initialize();
    for (var day = 0; day <= 7; day++) {
      await _plugin.cancel(_notificationId(habitId, day, false));
      await _plugin.cancel(_notificationId(habitId, day, true));
    }
  }

  static int _notificationId(int habitId, int weekday, bool nudge) =>
      habitId * 100 + (nudge ? 50 : 0) + weekday + 1;

  static Future<void> _handleResponse(NotificationResponse response) async {
    if (response.actionId == 'done') await _markHabitDone(response.payload);
  }

  @pragma('vm:entry-point')
  static Future<void> habitNotificationBackground(NotificationResponse response) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (response.actionId == 'done') await _markHabitDone(response.payload);
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
