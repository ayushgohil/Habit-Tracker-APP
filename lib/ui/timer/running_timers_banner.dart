import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/timer.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';
import 'timer_screen.dart';

/// Shows a tappable row on Home for every timer that is running or paused.
class RunningTimersBanner extends ConsumerWidget {
  const RunningTimersBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(timersProvider).valueOrNull ?? const <ActiveTimer>[];
    final habits = ref.watch(allHabitsProvider).valueOrNull ?? const <Habit>[];
    final rows = <Widget>[];
    for (final timer in timers) {
      final habit = habits.where((h) => h.id == timer.habitId).firstOrNull;
      if (habit == null) continue;
      final state = AppDatabase.stateOf(timer);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: EmberColors.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: Key('timer-banner-${habit.id}'),
              leading: Icon(
                state.isRunning ? Icons.timer_rounded : Icons.pause_circle_outline_rounded,
                color: EmberColors.ember,
              ),
              title: Text(habit.name),
              subtitle: Text(
                state.isRunning
                    ? 'Timer running'
                    : 'Paused at ${formatClock(state.elapsedSeconds(DateTime.now()))}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => TimerScreen(habitId: habit.id)),
              ),
            ),
          ),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(children: rows),
    );
  }
}
