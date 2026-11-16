import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/habit_icons.dart';
import '../../core/streak.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';

class AddHabitScreen extends ConsumerStatefulWidget {
  const AddHabitScreen({super.key});

  @override
  ConsumerState<AddHabitScreen> createState() => _AddHabitScreenState();
}

class _AddHabitScreenState extends ConsumerState<AddHabitScreen> {
  final _nameController = TextEditingController();

  String _iconKey = habitIcons.keys.first;
  Color _color = habitPalette.first;
  ScheduleType _type = ScheduleType.daily;
  int _weekdayMask = Schedule.allDaysMask;
  int _timesPerWeek = 3;
  int _dailyTarget = 1;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Give your habit a name.');
      return;
    }
    if (_type == ScheduleType.weekdays && _weekdayMask == 0) {
      _toast('Pick at least one day.');
      return;
    }

    setState(() => _saving = true);
    final existing = ref.read(habitsProvider).valueOrNull?.length ?? 0;
    await ref.read(habitActionsProvider).add(
          name: name,
          iconKey: _iconKey,
          colorValue: _color.toARGB32(),
          schedule: Schedule(
            type: _type,
            weekdayMask: _weekdayMask,
            timesPerWeek: _timesPerWeek,
          ),
          dailyTarget: _dailyTarget,
          sortOrder: existing,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New habit')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Habit name',
              counterText: '',
            ),
          ),
          const _SectionLabel('Icon'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in habitIcons.entries)
                _IconChoice(
                  icon: entry.value,
                  selected: entry.key == _iconKey,
                  color: _color,
                  onTap: () => setState(() => _iconKey = entry.key),
                ),
            ],
          ),
          const _SectionLabel('Colour'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in habitPalette)
                _ColorChoice(
                  color: c,
                  selected: c == _color,
                  onTap: () => setState(() => _color = c),
                ),
            ],
          ),
          const _SectionLabel('Repeat'),
          SegmentedButton<ScheduleType>(
            segments: const [
              ButtonSegment(value: ScheduleType.daily, label: Text('Daily')),
              ButtonSegment(value: ScheduleType.weekdays, label: Text('Days')),
              ButtonSegment(
                value: ScheduleType.timesPerWeek,
                label: Text('Weekly'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (selection) =>
                setState(() => _type = selection.first),
          ),
          if (_type == ScheduleType.weekdays) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(weekdayShortNames[i]),
                    selected: ((_weekdayMask >> i) & 1) == 1,
                    onSelected: (on) => setState(() {
                      _weekdayMask =
                          on ? _weekdayMask | (1 << i) : _weekdayMask & ~(1 << i);
                    }),
                  ),
              ],
            ),
          ],
          if (_type == ScheduleType.timesPerWeek) ...[
            const SizedBox(height: 12),
            _Stepper(
              value: _timesPerWeek,
              min: 1,
              max: 7,
              suffix: _timesPerWeek == 1 ? 'time a week' : 'times a week',
              onChanged: (v) => setState(() => _timesPerWeek = v),
            ),
          ],
          const _SectionLabel('Taps needed per day'),
          _Stepper(
            value: _dailyTarget,
            min: 1,
            max: 20,
            suffix: _dailyTarget == 1 ? 'tap' : 'taps',
            onChanged: (v) => setState(() => _dailyTarget = v),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Create habit'),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: EmberColors.textMuted,
              letterSpacing: 1.5,
            ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? color.withValues(alpha: 0.2) : EmberColors.surface,
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          color: selected ? color : EmberColors.textMuted,
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? EmberColors.text : Colors.transparent,
            width: 3,
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        const SizedBox(width: 16),
        Text(
          '$value $suffix',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: 16),
        IconButton.filledTonal(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
