import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/day.dart';
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
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddHabitScreen()));
  }

  Future<void> _pickDay(BuildContext context, WidgetRef ref, DateTime selected) async {
    final now = startOfDay(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: 'Choose a day to review or log',
    );
    if (picked != null) ref.read(todayProvider.notifier).state = startOfDay(picked);
  }

  Future<void> _handleHabitTap(BuildContext context, WidgetRef ref, HabitView view, DateTime day) async {
    final actions = ref.read(habitActionsProvider);
    final previousAmount = view.countToday;
    if (view.habit.taskType != HabitTaskType.timed.index) {
      await actions.tap(view, day);
    } else {
      final controller = TextEditingController();
      final minutes = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Log time · ${view.habit.name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Minutes completed', suffixText: 'min'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(int.tryParse(controller.text)), child: const Text('Save')),
          ],
        ),
      );
      controller.dispose();
      if (minutes == null || minutes <= 0 || !context.mounted) return;
      await actions.setTimedProgress(view, day, previousAmount + minutes * 60);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(view.isDone ? '${view.habit.name} marked incomplete' : '${view.habit.name} logged'),
        action: SnackBarAction(label: 'Undo', onPressed: () => actions.setAmount(view, day, previousAmount)),
      ),
    );
    HapticFeedback.selectionClick();
  }

  bool _allDueDone(List<HabitView> views, DateTime day) {
    final due = views.where((view) => view.schedule.isDue(day)).toList();
    return due.isNotEmpty && due.every((view) => view.isDone);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewsAsync = ref.watch(habitViewsProvider);
    final selectedDay = ref.watch(todayProvider);
    ref.listen<AsyncValue<List<HabitView>>>(habitViewsProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (before != null && after != null && !_allDueDone(before, selectedDay) && _allDueDone(after, selectedDay)) {
        HapticFeedback.heavyImpact();
      }
    });

    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _openAddHabit(context), child: const Icon(Icons.add_rounded)),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                day: selectedDay,
                views: viewsAsync.valueOrNull,
                onPickDay: () => _pickDay(context, ref, selectedDay),
                onToday: () => ref.read(todayProvider.notifier).state = startOfDay(DateTime.now()),
              ),
            ),
            ...viewsAsync.when<List<Widget>>(
              data: (views) {
                if (views.isEmpty) return [_EmptyState(onAdd: () => _openAddHabit(context))];
                return [
                  SliverToBoxAdapter(child: _GoldState(visible: _allDueDone(views, selectedDay))),
                  SliverToBoxAdapter(
                    child: _UpNext(
                      views: views,
                      day: selectedDay,
                      onTap: (view) => _handleHabitTap(context, ref, view, selectedDay),
                      onDetails: (view) => showHabitDetails(context, ref, view, selectedDay),
                      onReorder: (ids) => ref.read(habitActionsProvider).reorder(ids),
                    ),
                  ),
                  _buildGrid(context, ref, views, selectedDay),
                ];
              },
              loading: () => const [SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
              error: (error, _) => [SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Something went wrong: $error')))],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, WidgetRef ref, List<HabitView> list, DateTime day) {
    const columns = 3;
    const spacing = 14.0;
    const sidePadding = 20.0;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.crossAxisExtent - sidePadding * 2 - spacing * (columns - 1)) / columns;
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: sidePadding),
            child: Wrap(
              spacing: spacing,
              runSpacing: 22,
              children: [
                for (final view in list)
                  SizedBox(
                    width: tileWidth,
                    child: HabitTile(
                      name: view.habit.name,
                      icon: habitIconFor(view.habit.iconKey),
                      color: Color(view.habit.colorValue),
                      progress: view.progress,
                      streakLabel: view.streak.shortLabel,
                      streakActive: view.streak.length > 0,
                      onTap: () => _handleHabitTap(context, ref, view, day),
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        showHabitDetails(context, ref, view, day);
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
  const _Header({required this.day, required this.views, required this.onPickDay, required this.onToday});
  final DateTime day;
  final List<HabitView>? views;
  final VoidCallback onPickDay;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = views?.where((v) => v.schedule.isDue(day)).length ?? 0;
    final done = views?.where((v) => v.schedule.isDue(day) && v.isDone).length ?? 0;
    final isToday = dayKey(day) == dayKey(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded, color: EmberColors.ember, size: 20),
              const SizedBox(width: 6),
              Text('EMBER', style: textTheme.labelLarge?.copyWith(color: EmberColors.ember, letterSpacing: 3, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (!isToday) TextButton(onPressed: onToday, child: const Text('Today')),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPickDay,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isToday ? DateFormat('EEEE').format(day) : DateFormat('EEEE, d MMM').format(day),
                            style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(isToday ? DateFormat('d MMMM').format(day) : 'Past day · edit your history',
                            style: textTheme.titleSmall?.copyWith(color: EmberColors.textMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.calendar_month_rounded, color: EmberColors.glow),
                ],
              ),
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            Text('$done of $total due habits done', style: textTheme.bodyMedium?.copyWith(color: EmberColors.glow)),
          ],
        ],
      ),
    );
  }
}

class _GoldState extends StatelessWidget {
  const _GoldState({required this.visible});
  final bool visible;
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
    child: visible
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(colors: [Color(0xFF5A4218), Color(0xFF342716)]),
                border: Border.all(color: const Color(0xFFFFD36A).withValues(alpha: .65)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD36A), size: 30),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('All sparks lit', style: TextStyle(color: Color(0xFFFFD36A), fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('Every habit due today is complete. Keep the glow going.', style: TextStyle(color: Color(0xFFFFE9B0))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.views, required this.day, required this.onTap, required this.onDetails, required this.onReorder});
  final List<HabitView> views;
  final DateTime day;
  final ValueChanged<HabitView> onTap;
  final ValueChanged<HabitView> onDetails;
  final ValueChanged<List<int>> onReorder;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...views.where((v) => v.schedule.isDue(day) && !v.isDone),
      ...views.where((v) => !v.schedule.isDue(day) || v.isDone),
    ];
    final pending = ordered.where((v) => v.schedule.isDue(day) && !v.isDone).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('UP NEXT', style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.8, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$pending remaining', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: EmberColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(color: EmberColors.surface, borderRadius: BorderRadius.circular(18)),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: ordered.length,
              onReorderItem: (oldIndex, newIndex) {
                final moved = [...ordered];
                final item = moved.removeAt(oldIndex);
                moved.insert(newIndex, item);
                onReorder(moved.map((v) => v.habit.id).toList());
                HapticFeedback.selectionClick();
              },
              itemBuilder: (context, index) {
                final view = ordered[index];
                final done = view.isDone;
                final due = view.schedule.isDue(day);
                return ListTile(
                  key: ValueKey(view.habit.id),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(view.habit.colorValue).withValues(alpha: .16),
                    child: Icon(done ? Icons.check_rounded : habitIconFor(view.habit.iconKey), size: 18, color: Color(view.habit.colorValue)),
                  ),
                  title: Text(view.habit.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(done ? 'Completed' : due ? 'Ready when you are' : view.schedule.describe(),
                      style: TextStyle(color: done ? EmberColors.glow : EmberColors.textMuted, fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: done ? 'Undo completion' : 'Mark complete',
                        onPressed: due ? () => onTap(view) : null,
                        icon: Icon(done ? Icons.check_circle_rounded : Icons.circle_outlined,
                            color: done ? const Color(0xFFFFD36A) : EmberColors.textMuted),
                      ),
                      ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle_rounded, color: EmberColors.textMuted)),
                    ],
                  ),
                  onTap: () => onDetails(view),
                );
              },
            ),
          ),
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
              const Icon(Icons.local_fire_department_rounded, size: 56, color: EmberColors.ember),
              const SizedBox(height: 16),
              Text('Light your first ember', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Add a habit and keep it burning every day.', textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: EmberColors.textMuted)),
              const SizedBox(height: 24),
              FilledButton(onPressed: onAdd, child: const Text('Add a habit')),
            ],
          ),
        ),
      ),
    );
  }
}
