import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/habit_icons.dart';
import '../../core/streak.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';
import '../add_habit/add_habit_screen.dart';
import 'habit_details_sheet.dart';
import 'habit_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _openAddHabit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddHabitScreen()),
    );
  }

  Future<void> _handleHabitTap(
    BuildContext context,
    WidgetRef ref,
    HabitView view,
    DateTime day,
  ) async {
    HapticFeedback.lightImpact();
    final actions = ref.read(habitActionsProvider);
    if (view.habit.taskType != HabitTaskType.timed.index) {
      await actions.tap(view, day);
      return;
    }

    final controller = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Log time · ${view.habit.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes completed',
            suffixText: 'min',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              int.tryParse(controller.text),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes == null || minutes <= 0 || !context.mounted) return;
    await actions.setTimedProgress(
      view,
      day,
      view.countToday + minutes * 60,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(habitViewsProvider);
    final today = ref.watch(todayProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddHabit(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(today: today, views: views.valueOrNull),
            ),
            ...views.when<List<Widget>>(
              data: (list) => list.isEmpty
                  ? [_EmptyState(onAdd: () => _openAddHabit(context))]
                  : [_buildGrid(context, ref, list, today)],
              loading: () => const [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Something went wrong: $error')),
                ),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    List<HabitView> list,
    DateTime today,
  ) {
    const columns = 3;
    const spacing = 14.0;
    const sidePadding = 20.0;

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.crossAxisExtent -
                sidePadding * 2 -
                spacing * (columns - 1)) /
            columns;

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: sidePadding),
            child: Wrap(
              spacing: spacing,
              runSpacing: 22,
              children: [
                for (final v in list)
                  SizedBox(
                    width: tileWidth,
                    child: HabitTile(
                      name: v.habit.name,
                      icon: habitIconFor(v.habit.iconKey),
                      color: Color(v.habit.colorValue),
                      progress: v.progress,
                      streakLabel: v.streak.shortLabel,
                      streakActive: v.streak.length > 0,
                      onTap: () => _handleHabitTap(context, ref, v, today),
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        showHabitDetails(context, ref, v);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.today, required this.views});

  final DateTime today;
  final List<HabitView>? views;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = views?.length ?? 0;
    final done = views?.where((v) => v.isDone).length ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: EmberColors.ember,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                'EMBER',
                style: textTheme.labelLarge?.copyWith(
                  color: EmberColors.ember,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            DateFormat('EEEE').format(today),
            style: textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            DateFormat('d MMMM').format(today),
            style:
                textTheme.titleMedium?.copyWith(color: EmberColors.textMuted),
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$done of $total done today',
              style: textTheme.bodyMedium?.copyWith(color: EmberColors.glow),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                size: 56,
                color: EmberColors.ember,
              ),
              const SizedBox(height: 16),
              Text('Light your first ember', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Add a habit and keep it burning every day.',
                textAlign: TextAlign.center,
                style:
                    textTheme.bodyMedium?.copyWith(color: EmberColors.textMuted),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onAdd, child: const Text('Add a habit')),
            ],
          ),
        ),
      ),
    );
  }
}
