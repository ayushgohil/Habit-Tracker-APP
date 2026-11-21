import 'package:flutter/widgets.dart';

import '../core/day.dart';
import '../core/streak.dart';
import '../data/database.dart';
import '../data/day_start.dart';
import '../data/providers.dart';
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
  await db.setCompletion(habitId: habitId, day: dayKey(day), amount: view.countToday + view.habit.stepSize);
  return true;
}

/// Runs when a widget row is tapped, even if the app is closed.
@pragma('vm:entry-point')
Future<void> emberWidgetBackground(Uri? uri) async {
  if (uri == null || uri.host != 'tap') return;
  final id = int.tryParse(uri.queryParameters['id'] ?? '');
  if (id == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  await loadDayStart();
  final db = AppDatabase();
  try {
    final day = currentDay();
    await logTapFromWidget(db, id, day);
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
