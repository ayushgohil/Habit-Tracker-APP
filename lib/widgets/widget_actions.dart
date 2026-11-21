import 'package:flutter/widgets.dart';

import '../core/day.dart';
import '../core/streak.dart';
import '../data/database.dart';
import '../data/day_start.dart';
import '../data/providers.dart';
import '../health/health_writer.dart';
import '../notifications/habit_notification_service.dart';
import 'home_screen_widget.dart';
import 'widget_cards.dart';

/// Logs one tap for [habitId] on [day]. Returns false (and changes nothing)
/// when the habit is gone, not scheduled that day, already done, timed or
/// linked to Health Connect: those are done inside the app.
Future<bool> logTapFromWidget(AppDatabase db, int habitId, DateTime day) async {
  final views = await loadViewsOn(db, day);
  final view = views.where((v) => v.habit.id == habitId).firstOrNull;
  if (view == null) return false;
  if (view.habit.taskType == HabitTaskType.timed.index || view.habit.healthMetric != 0) return false;
  if (!view.schedule.isDue(day) || view.isDone) return false;
  final amount = view.countToday + view.habit.stepSize;
  await db.setCompletion(habitId: habitId, day: dayKey(day), amount: amount);
  await mirrorToHealth(view.habit, view.countToday, amount, day);
  return true;
}

/// Marks a plain habit done for [day] in one go (for automation apps).
Future<bool> completeFromAutomation(AppDatabase db, int habitId, DateTime day) async {
  final views = await loadViewsOn(db, day);
  final view = views.where((v) => v.habit.id == habitId).firstOrNull;
  if (view == null || view.habit.healthMetric != 0 || view.habit.limitMode) return false;
  if (!view.schedule.isDue(day) || view.isDone) return false;
  await db.setCompletion(habitId: habitId, day: dayKey(day), amount: view.target);
  await mirrorToHealth(view.habit, view.countToday, view.target, day);
  return true;
}

Future<bool> _isTimed(AppDatabase db, int habitId) async {
  final habit = await (db.select(db.habits)..where((h) => h.id.equals(habitId))).getSingleOrNull();
  return habit != null && habit.taskType == HabitTaskType.timed.index;
}

/// Runs when a widget row is tapped, even if the app is closed.
@pragma('vm:entry-point')
Future<void> emberWidgetBackground(Uri? uri) async {
  const hosts = {'tap', 'complete', 'start', 'stop'};
  if (uri == null || !hosts.contains(uri.host)) return;
  final id = int.tryParse(uri.queryParameters['id'] ?? '');
  if (id == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  await loadDayStart();
  final db = AppDatabase();
  try {
    final day = currentDay();
    switch (uri.host) {
      case 'tap':
        await logTapFromWidget(db, id, day);
      case 'complete':
        await completeFromAutomation(db, id, day);
      case 'start':
        if (await _isTimed(db, id)) await HabitActions(db).startTimer(id);
      case 'stop':
        if (await _isTimed(db, id)) await HabitActions(db).finishTimer(id);
    }
    final views = await loadViewsOn(db, day);
    if (views.any((v) => v.habit.id == id && v.isDone)) {
      await HabitNotificationService.instance.cancelToday(id);
    }
    // Redraw the widget right away with the new progress.
    await HomeScreenWidget.instance.sync(await loadViewsOn(db, day), day);
    await WidgetCards.instance.sync(db, day);
  } catch (error) {
    debugPrint('Ember widget tap: $error');
  } finally {
    await db.close();
  }
}
