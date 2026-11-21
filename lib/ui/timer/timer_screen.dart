import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/day.dart';
import '../../core/goals.dart';
import '../../core/timer.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';

/// Sessions longer than this (4 hours) ask for confirmation before saving.
const longSessionSeconds = 4 * 3600;

/// Full-screen timer for a timed habit.
class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key, required this.habitId});
  final int habitId;

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Redraws every second, but only while a timer is actually running.
  void _syncTicker(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(allHabitsProvider).valueOrNull;
    final timers = ref.watch(timersProvider).valueOrNull;
    final completions = ref.watch(completionsProvider).valueOrNull;
    final goals = ref.watch(goalsProvider).valueOrNull;
    final habit = habits?.where((h) => h.id == widget.habitId).firstOrNull;
    if (habits == null || timers == null || completions == null || goals == null || habit == null) {
      _syncTicker(false);
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final row = timers.where((t) => t.habitId == widget.habitId).firstOrNull;
    final state = row == null ? const TimerState() : AppDatabase.stateOf(row);
    _syncTicker(state.isRunning);

    final now = DateTime.now();
    final elapsed = state.elapsedSeconds(now);
    // The goal and what is already logged are for the day the timer belongs
    // to (the day it started, or today), so the ring starts from time that is
    // already counted.
    final day = row?.day ?? currentDayKey(now);
    final logged = completions
            .where((c) => c.habitId == habit.id && c.day == day)
            .firstOrNull
            ?.amount ??
        0;
    final target = timelineFor(habit, goals).targetOn(parseDayKey(day));
    final total = logged + elapsed;
    final color = Color(habit.colorValue);
    final actions = ref.read(habitActionsProvider);
    final reached = target > 0 && total >= target;
    final over = reached ? total - target : 0;
    final plan = SessionPlan(goalSeconds: target, sessionSeconds: habit.sessionSeconds);
    final session = plan.sessionAt(total);

    return Scaffold(
      appBar: AppBar(title: Text(habit.name, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: plan.isSplit && !reached
                            ? plan.sessionProgress(total)
                            : (target <= 0 ? 0.0 : (total / target).clamp(0.0, 1.0).toDouble()),
                        strokeWidth: 12,
                        strokeCap: StrokeCap.round,
                        backgroundColor: EmberColors.track,
                        color: reached ? EmberColors.glow : color,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatClock(elapsed),
                          key: const Key('timer-clock'),
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        const SizedBox(height: 4),
                        if (plan.isSplit && !reached)
                          Text(
                            'Session $session of ${plan.count}',
                            key: const Key('timer-session'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        Text(
                          reached
                              ? (over > 0 ? 'Goal reached · +${formatClock(over)} over' : 'Goal reached')
                              : (plan.isSplit
                                  ? '${formatClock(plan.secondsIntoSession(total))} of ${formatClock(plan.lengthOf(session))}'
                                  : 'Goal ${formatClock(target)}'),
                          key: const Key('timer-goal'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: EmberColors.textMuted),
                        ),
                        if (logged > 0)
                          Text(
                            '${formatClock(logged)} already logged',
                            key: const Key('timer-logged'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: EmberColors.textMuted),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('timer-toggle'),
                  onPressed: () => state.isRunning ? actions.pauseTimer(habit.id) : actions.startTimer(habit.id),
                  child: Text(state.isRunning ? 'Pause' : (row == null ? 'Start' : 'Resume')),
                ),
              ),
              if (row != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    key: const Key('timer-save'),
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      // A timer left running by mistake would save hours that
                      // were never worked, so ask before saving a very long one.
                      if (elapsed > longSessionSeconds) {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Save a very long session?'),
                            content: Text('This timer has run for ${formatClock(elapsed)}. Save all of it?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                      }
                      final seconds = await actions.finishTimer(habit.id);
                      messenger.showSnackBar(SnackBar(
                        content: Text(seconds > 0 ? '${habit.name}: ${formatClock(seconds)} saved' : 'Nothing to save yet'),
                      ));
                      navigator.pop();
                    },
                    child: const Text('Save time'),
                  ),
                ),
                TextButton(
                  key: const Key('timer-discard'),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await actions.discardTimer(habit.id);
                    navigator.pop();
                  },
                  child: const Text('Discard'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
