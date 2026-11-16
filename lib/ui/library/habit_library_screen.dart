import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';

class HabitLibraryScreen extends ConsumerWidget {
  const HabitLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paused = ref.watch(pausedHabitsProvider);
    final archived = ref.watch(archivedHabitsProvider);
    final active = ref.watch(habitsProvider);
    final actions = ref.read(habitActionsProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Habit library'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Reorder'),
              Tab(text: 'Paused'),
              Tab(text: 'Archived'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            active.when(
              data: (items) => ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex--;
                  final reordered = [...items];
                  final item = reordered.removeAt(oldIndex);
                  reordered.insert(newIndex, item);
                  await actions.reorder(reordered.map((h) => h.id).toList());
                },
                itemBuilder: (context, index) {
                  final habit = items[index];
                  return ListTile(
                    key: ValueKey(habit.id),
                    leading: const Icon(Icons.drag_handle),
                    title: Text(habit.name),
                    subtitle: const Text('Drag to change dashboard order'),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load habits: $e')),
            ),
            _HabitList(
              state: paused,
              empty: 'No paused habits',
              actionLabel: 'Resume',
              icon: Icons.play_arrow_rounded,
              onAction: actions.resume,
            ),
            _HabitList(
              state: archived,
              empty: 'No archived habits',
              actionLabel: 'Restore',
              icon: Icons.unarchive_outlined,
              onAction: actions.restore,
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitList extends StatelessWidget {
  const _HabitList({
    required this.state,
    required this.empty,
    required this.actionLabel,
    required this.icon,
    required this.onAction,
  });
  final AsyncValue<List<Habit>> state;
  final String empty;
  final String actionLabel;
  final IconData icon;
  final Future<void> Function(int) onAction;

  @override
  Widget build(BuildContext context) => state.when(
        data: (items) => items.isEmpty
            ? Center(
                child: Text(
                  empty,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: EmberColors.textMuted,
                      ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final habit = items[index];
                  return ListTile(
                    title: Text(habit.name),
                    trailing: TextButton.icon(
                      onPressed: () => onAction(habit.id),
                      icon: Icon(icon),
                      label: Text(actionLabel),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load habits: $e')),
      );
}
