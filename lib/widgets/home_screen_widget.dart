import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/streak.dart';
import '../core/widget_summary.dart';
import '../data/providers.dart';

/// Pushes today's habits to the Android home-screen widget.
class HomeScreenWidget {
  HomeScreenWidget._();
  static final instance = HomeScreenWidget._();

  static const _androidName = 'EmberWidgetProvider';
  static const _qualifiedName = 'com.nextlyr.ember.EmberWidgetProvider';

  String? _lastSent;

  /// What the widget should show for [views]. Habits not scheduled today are left out.
  static WidgetSummary summaryFor(List<HabitView> views, DateTime day) {
    return buildWidgetSummary([
      for (final v in views)
        if (v.schedule.isDue(day))
          WidgetHabit(
            name: v.habit.name,
            done: v.isDone,
            count: v.countToday,
            target: v.target,
            timed: v.habit.taskType == HabitTaskType.timed.index,
          ),
    ]);
  }

  Future<void> sync(List<HabitView> views, DateTime day) async {
    try {
      final summary = summaryFor(views, day);
      final data = <String, String>{
        'ember_summary': summary.summary,
        for (var i = 0; i < 6; i++) ...{
          'ember_row$i': i < summary.rows.length ? summary.rows[i].text : '',
          'ember_done$i': i < summary.rows.length && summary.rows[i].done ? '1' : '0',
        },
      };
      // Skip the update when nothing changed.
      final fingerprint = data.entries.map((e) => '${e.key}=${e.value}').join('|');
      if (fingerprint == _lastSent) return;
      for (final e in data.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(androidName: _androidName, qualifiedAndroidName: _qualifiedName);
      _lastSent = fingerprint;
    } catch (error) {
      // No widget plugin (tests) or no widget placed: never a reason to fail.
      debugPrint('Ember widget: $error');
    }
  }
}
