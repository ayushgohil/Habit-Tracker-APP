import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/day.dart';
import '../../core/habit_icons.dart';
import '../../core/habit_order.dart';
import '../../core/streak.dart';
import '../../data/providers.dart';
import '../../health/health_sync.dart';
import '../../theme/ember_theme.dart';
import '../add_habit/add_habit_screen.dart';
import '../appearance/appearance_sheet.dart';
import '../common/text_dialogs.dart';
import '../backup/backup_screen.dart';
import '../library/habit_library_screen.dart';
import '../timer/running_timers_banner.dart';
import 'habit_details_sheet.dart';
import 'habit_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _openAddHabit(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AddHabitScreen()));
  }

  void _openLibrary(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HabitLibraryScreen()));
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
    if (view.habit.healthMetric != 0) {
      // Filled in from Health Connect: tapping refreshes it instead of logging by hand.
      final changed = await ref.read(healthSyncProvider).syncNow();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(changed > 0 ? 'Updated from Health Connect' : 'Nothing new in Health Connect')),
      );
      return;
    }
    final previousAmount = view.countToday;
    final String message;
    if (view.habit.taskType != HabitTaskType.timed.index) {
      await actions.tap(view, day);
      message = view.isDone ? '${view.habit.name} marked incomplete' : '${view.habit.name} logged';
    } else {
      final minutes = await showLogTimeDialog(
        context,
        habitName: view.habit.name,
        canClear: previousAmount > 0,
      );
      if (minutes == null || !context.mounted) return;
      if (minutes == clearLoggedTime) {
        await actions.setTimedProgress(view, day, 0);
        message = '${view.habit.name} time cleared';
      } else {
        await actions.setTimedProgress(view, day, previousAmount + minutes * 60);
        message = '${view.habit.name}: $minutes min logged';
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: () => actions.setAmount(view, day, previousAmount)),
      ),
    );
    HapticFeedback.selectionClick();
  }

  Future<void> _editDayNote(BuildContext context, WidgetRef ref, DateTime day) async {
    final actions = ref.read(habitActionsProvider);
    final existing = await actions.loadNote(day);
    if (!context.mounted) return;
    final note = await showNoteDialog(
      context,
      title: 'Note · ${DateFormat('d MMM yyyy').format(day)}',
      initialText: existing ?? '',
      hintText: 'What happened today?',
    );
    if (note != null) await actions.saveNote(day, note);
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
                onNote: () => _editDayNote(context, ref, selectedDay),
                onLibrary: () => _openLibrary(context),
                onBackup: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackupScreen())),
              ),
            ),
            const SliverToBoxAdapter(child: RunningTimersBanner()),
            ...viewsAsync.when<List<Widget>>(
              data: (views) {
                if (views.isEmpty) {
                  return [
                    _EmptyState(
                      // Habits only exist from their start date, so an empty
                      // past day doesn't mean the person has no habits.
                      pastDay: dayKey(selectedDay) != dayKey(DateTime.now()),
                      onAdd: () => _openAddHabit(context),
                      onToday: () => ref.read(todayProvider.notifier).state = startOfDay(DateTime.now()),
                    ),
                  ];
                }
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
  const _Header({required this.day, required this.views, required this.onPickDay, required this.onToday, required this.onNote, required this.onLibrary, required this.onBackup});
  final DateTime day;
  final List<HabitView>? views;
  final VoidCallback onPickDay;
  final VoidCallback onToday;
  final VoidCallback onNote;
  final VoidCallback onLibrary;
  final VoidCallback onBackup;

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
              Icon(Icons.local_fire_department_rounded, color: EmberColors.ember, size: 20),
              const SizedBox(width: 6),
              Text('EMBER', style: textTheme.labelLarge?.copyWith(color: EmberColors.ember, letterSpacing: 3, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'Daily note',
                onPressed: onNote,
                icon: const Icon(Icons.note_alt_outlined),
              ),
              IconButton(
                tooltip: 'Habit library',
                onPressed: onLibrary,
                icon: const Icon(Icons.inventory_2_outlined),
              ),
              IconButton(
                key: const Key('appearance-button'),
                tooltip: 'Appearance',
                onPressed: () => showAppearanceSheet(context),
                icon: const Icon(Icons.palette_outlined),
              ),
              IconButton(
                tooltip: 'Back up & restore',
                onPressed: onBackup,
                icon: const Icon(Icons.cloud_upload_outlined),
              ),
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
                  if (!isToday) TextButton(onPressed: onToday, child: const Text('Today')),
                  Icon(Icons.calendar_month_rounded, color: EmberColors.glow),
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

/// With more habits than this, the list starts folded so the rings stay in view.
const upNextAutoCollapseAbove = 4;

class _UpNext extends StatefulWidget {
  const _UpNext({required this.views, required this.day, required this.onTap, required this.onDetails, required this.onReorder});
  final List<HabitView> views;
  final DateTime day;
  final ValueChanged<HabitView> onTap;
  final ValueChanged<HabitView> onDetails;
  final ValueChanged<List<int>> onReorder;

  @override
  State<_UpNext> createState() => _UpNextState();
}

class _UpNextState extends State<_UpNext> {
  /// null until the person taps the header; then their choice wins.
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final views = widget.views;
    final day = widget.day;
    final onTap = widget.onTap;
    final onDetails = widget.onDetails;
    final onReorder = widget.onReorder;
    final open = _open ?? views.length <= upNextAutoCollapseAbove;
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
          InkWell(
            key: const Key('up-next-toggle'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text('UP NEXT', style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.8, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('$pending remaining', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: EmberColors.textMuted)),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, color: EmberColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: open ? _list(context, ordered, views, day, onTap, onDetails, onReorder) : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<HabitView> ordered,
    List<HabitView> views,
    DateTime day,
    ValueChanged<HabitView> onTap,
    ValueChanged<HabitView> onDetails,
    ValueChanged<List<int>> onReorder,
  ) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Material (not a coloured DecoratedBox) so the ListTiles can paint
          // their tap ripple instead of having it hidden behind the background.
          Material(
            color: EmberColors.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: ordered.length,
              onReorderItem: (oldIndex, newIndex) {
                final moved = [...ordered];
                final item = moved.removeAt(oldIndex);
                moved.insert(newIndex, item);
                // Only reorder inside the dragged habit's own group, so the
                // pending-first display order never leaks into the saved order.
                final itemIsPending = item.schedule.isDue(day) && !item.isDone;
                bool isPending(HabitView v) => v.schedule.isDue(day) && !v.isDone;
                onReorder(
                  reorderWithinGroup(
                    persisted: views.map((v) => v.habit.id).toList(),
                    displayedAfterMove: moved.map((v) => v.habit.id).toList(),
                    group: {
                      for (final v in views)
                        if (isPending(v) == itemIsPending) v.habit.id,
                    },
                  ),
                );
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
                      ReorderableDragStartListener(index: index, child: Icon(Icons.drag_handle_rounded, color: EmberColors.textMuted)),
                    ],
                  ),
                  onTap: () => onDetails(view),
                );
              },
            ),
          ),
        ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.pastDay, required this.onAdd, required this.onToday});
  final bool pastDay;
  final VoidCallback onAdd;
  final VoidCallback onToday;
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
              Icon(Icons.local_fire_department_rounded, size: 56, color: EmberColors.ember),
              const SizedBox(height: 16),
              Text(pastDay ? 'No habits on this day' : 'Light your first ember', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                  pastDay
                      ? 'Your habits start on a later day. Go back to today to log them.'
                      : 'Add a habit and keep it burning every day.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: EmberColors.textMuted)),
              const SizedBox(height: 24),
              if (pastDay)
                FilledButton(onPressed: onToday, child: const Text('Back to today'))
              else
                FilledButton(onPressed: onAdd, child: const Text('Add a habit')),
            ],
          ),
        ),
      ),
    );
  }
}
