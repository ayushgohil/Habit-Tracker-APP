import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/habit_icons.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';
import '../add_habit/add_habit_screen.dart';
import '../common/text_dialogs.dart';
import '../stats/habit_stats_screen.dart';

Future<void> showHabitDetails(BuildContext context, WidgetRef ref, HabitView view, DateTime day) {
  final actions = ref.read(habitActionsProvider);
  final habit = view.habit;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: EmberColors.surfaceHigh,
    showDragHandle: true,
    // Without this the sheet is capped at 9/16 of the screen height and the
    // menu overflows on most phones.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        // Scrollable so a short screen or a large font never overflows.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(habit.colorValue).withValues(alpha: .18),
                  child: Icon(habitIconFor(habit.iconKey), color: Color(habit.colorValue)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(habit.name, style: Theme.of(context).textTheme.titleLarge),
                      Text(view.schedule.describe(), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: EmberColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _Stat(label: 'Current', value: view.stats.currentStreak.longLabel),
                _Stat(label: 'Best', value: view.stats.bestStreak.longLabel),
                _Stat(label: 'Completion', value: '${(view.stats.completionRate * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insights_rounded),
              title: const Text('Stats & history'),
              subtitle: const Text('Calendar, streaks and charts'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HabitStatsScreen(habitId: habit.id)));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.note_alt_outlined),
              title: const Text('Day note'),
              subtitle: Text('Add a note for ${DateFormat('d MMM yyyy').format(day)}'),
              onTap: () async {
                final existing = await actions.loadNote(day);
                if (!sheetContext.mounted) return;
                final note = await showNoteDialog(
                  sheetContext,
                  title: 'Daily note',
                  initialText: existing ?? '',
                  hintText: 'How did this day go?',
                  maxLength: 500,
                );
                if (note != null) await actions.saveNote(day, note);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit habit'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddHabitScreen(habit: habit)));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(habit.pausedAt == null ? Icons.pause_circle_outline : Icons.play_circle_outline),
              title: Text(habit.pausedAt == null ? 'Pause' : 'Resume'),
              subtitle: const Text('Temporarily exclude it from your daily list'),
              onTap: () async {
                if (habit.pausedAt == null) {
                  await actions.pause(habit.id);
                } else {
                  await actions.resume(habit.id);
                }
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Archive'),
              subtitle: const Text('Hide it but keep its history'),
              onTap: () async {
                await actions.archive(habit.id);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              subtitle: const Text('Remove it and its history permanently'),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: sheetContext,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Delete habit?'),
                    content: Text('"${habit.name}" and its whole history will be removed. This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await actions.delete(habit.id);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: EmberColors.textMuted)),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}
