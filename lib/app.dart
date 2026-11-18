import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/day.dart';
import 'data/providers.dart';
import 'notifications/habit_notification_service.dart';
import 'theme/ember_theme.dart';
import 'ui/home/home_screen.dart';

class EmberApp extends ConsumerStatefulWidget {
  const EmberApp({super.key});

  @override
  ConsumerState<EmberApp> createState() => _EmberAppState();
}

class _EmberAppState extends ConsumerState<EmberApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncReminders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The calendar day the app last saw as "today".
  DateTime _lastToday = startOfDay(DateTime.now());

  /// Rolls "today" over when the app is reopened after midnight.
  ///
  /// Only a selection that was showing the old "today" moves forward. If the
  /// person was reviewing or logging a past day, resuming the app must not
  /// bounce them back to today.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _syncReminders();
    _refreshTimers();
    final today = startOfDay(DateTime.now());
    if (today == _lastToday) return;
    if (ref.read(todayProvider) == _lastToday) {
      ref.read(todayProvider.notifier).state = today;
    }
    _lastToday = today;
  }

  /// Notification buttons (Pause / Save) change the database from another
  /// isolate, which the open app can't see, so re-read the timers on resume.
  void _refreshTimers() {
    try {
      final db = ref.read(databaseProvider);
      db.markTablesUpdated([db.activeTimers, db.completions]);
    } catch (_) {}
  }

  Future<void> _syncReminders() async {
    try {
      final db = ref.read(databaseProvider);
      final habits = await db.select(db.habits).get();
      await HabitNotificationService.instance.syncAll(habits);
    } catch (_) {
      // A notification setup failure must never prevent the habit tracker opening.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ember',
      debugShowCheckedModeBanner: false,
      theme: emberTheme(),
      home: const HomeScreen(),
    );
  }
}
