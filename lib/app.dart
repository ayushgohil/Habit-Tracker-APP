import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/day.dart';
import 'data/providers.dart';
import 'core/streak.dart';
import 'health/health_sync.dart';
import 'notifications/habit_notification_service.dart';
import 'theme/ember_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/home/home_screen.dart';
import 'ui/timer/timer_screen.dart';
import 'widgets/home_screen_widget.dart';
import 'widgets/launcher_shortcuts.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

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
    LauncherShortcuts.instance.initialize(_onShortcut);
    _syncHealth();
    ref.listenManual<String>(themeIdProvider, (_, __) => _repaintEverything());
    ref.listenManual<AsyncValue<List<HabitView>>>(
      liveTodayViewsProvider,
      (_, next) => _onTodayChanged(next),
      fireImmediately: true,
    );
  }

  /// Colours are read as widgets build, so after the look changes every widget
  /// is asked to build again (the same trick Flutter uses for hot reload).
  void _repaintEverything() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void visit(Element element) {
        element.markNeedsBuild();
        element.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
    });
  }

  /// A shortcut tapped before the habits have loaded waits here.
  int? _pendingShortcut;

  void _onShortcut(int habitId) {
    final views = ref.read(liveTodayViewsProvider).valueOrNull;
    if (views == null) {
      _pendingShortcut = habitId;
      return;
    }
    _pendingShortcut = null;
    final view = views.where((v) => v.habit.id == habitId).firstOrNull;
    if (view == null) return;
    if (view.habit.taskType == HabitTaskType.timed.index) {
      _navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => TimerScreen(habitId: habitId)));
      return;
    }
    if (view.isDone) return;
    ref.read(habitActionsProvider).tap(view, startOfDay(DateTime.now()));
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text('Logged ${view.habit.name}')));
  }

  /// Keeps the home-screen widget and launcher shortcuts in step with today.
  void _onTodayChanged(AsyncValue<List<HabitView>> next) {
    final views = next.valueOrNull;
    if (views == null) return;
    final today = startOfDay(DateTime.now());
    HomeScreenWidget.instance.sync(views, today);
    LauncherShortcuts.instance.sync(views, today);
    final pending = _pendingShortcut;
    if (pending != null) _onShortcut(pending);
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
    _syncHealth();
    // The day may have changed while the app was away.
    ref.invalidate(liveTodayViewsProvider);
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

  /// Pulls steps, workouts and sleep for habits linked to Health Connect.
  void _syncHealth() {
    ref.read(healthSyncProvider).syncNow();
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
    final palette = paletteById(ref.watch(themeIdProvider));
    EmberColors.use(palette);
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Ember',
      debugShowCheckedModeBanner: false,
      theme: emberTheme(palette),
      home: const HomeScreen(),
    );
  }
}
