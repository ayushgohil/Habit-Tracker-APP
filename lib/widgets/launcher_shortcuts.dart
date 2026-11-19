import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import '../core/streak.dart';
import '../data/providers.dart';

/// Long-press shortcuts on the launcher icon: one per habit still to do today.
class LauncherShortcuts {
  LauncherShortcuts._();
  static final instance = LauncherShortcuts._();

  static const _prefix = 'habit:';
  static const maxShortcuts = 4;

  final _actions = const QuickActions();
  String? _lastSent;

  /// The habit id inside a shortcut type, or null if it is not one of ours.
  static int? habitIdOf(String type) =>
      type.startsWith(_prefix) ? int.tryParse(type.substring(_prefix.length)) : null;

  /// Shortcut title for a habit: timed habits open their timer.
  static String titleFor(HabitView view) =>
      view.habit.taskType == HabitTaskType.timed.index ? 'Time ${view.habit.name}' : 'Log ${view.habit.name}';

  /// Starts listening. [onShortcut] gets the habit id when one is tapped,
  /// including when it was the shortcut that launched the app.
  void initialize(void Function(int habitId) onShortcut) {
    try {
      _actions.initialize((type) {
        final id = habitIdOf(type);
        if (id != null) onShortcut(id);
      });
    } catch (error) {
      debugPrint('Ember shortcuts: $error');
    }
  }

  /// Offers shortcuts for the first habits that are not done yet.
  Future<void> sync(List<HabitView> views, DateTime day) async {
    try {
      final todo = [
        for (final v in views)
          if (v.schedule.isDue(day) && !v.isDone) v,
      ].take(maxShortcuts).toList();
      final key = todo.map((v) => '${v.habit.id}:${titleFor(v)}').join('|');
      if (key == _lastSent) return;
      await _actions.setShortcutItems([
        for (final v in todo)
          ShortcutItem(type: '$_prefix${v.habit.id}', localizedTitle: titleFor(v)),
      ]);
      _lastSent = key;
    } catch (error) {
      debugPrint('Ember shortcuts: $error');
    }
  }
}
