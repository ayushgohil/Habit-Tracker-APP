import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/timer.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';

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
    final habit = habits?.where((h) => h.id == widget.habitId).firstOrNull;
    if (habits == null || timers == null || habit == null) {
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
    final target = habit.targetDurationSeconds;
    final color = Color(habit.colorValue);
    final actions = ref.read(habitActionsProvider);
    final reached = target > 0 && elapsed >= target;

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
                        value: state.progress(now, target),
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
                        Text(
                          reached ? 'Goal reached' : 'Goal ${formatClock(target)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: EmberColors.textMuted),
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
