import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/habit_icons.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';

/// Bottom sheet opened by long-pressing a habit.
Future<void> showHabitDetails(
  BuildContext context,
  WidgetRef ref,
  HabitView view,
) {
  final actions = ref.read(habitActionsProvider);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: EmberColors.surfaceHigh,
    showDragHandle: true,
    builder: (sheetContext) => _DetailsSheet(
      view: view,
      onArchive: () async {
        await actions.archive(view.habit.id);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
      onDelete: () async {
        final confirmed = await showDialog<bool>(
          context: sheetContext,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete habit?'),
            content: Text(
              '"${view.habit.name}" and its whole history will be removed. '
              'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await actions.delete(view.habit.id);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
    ),
  );
}

class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({
    required this.view,
    required this.onArchive,
    required this.onDelete,
  });

  final HabitView view;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Color(view.habit.colorValue);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: Icon(habitIconFor(view.habit.iconKey), color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.habit.name,
                        style: textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        view.schedule.describe(),
                        style: textTheme.bodyMedium
                            ?.copyWith(color: EmberColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: EmberColors.glow,
                ),
                const SizedBox(width: 8),
                Text(
                  view.streak.length == 0
                      ? 'No streak yet'
                      : '${view.streak.longLabel} streak',
                  style: textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Archive'),
              subtitle: const Text('Hide it but keep the history'),
              onTap: onArchive,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              subtitle: const Text('Remove it and its history'),
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
