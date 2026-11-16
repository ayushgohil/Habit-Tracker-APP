import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/habit_icons.dart';
import '../../core/streak.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../theme/ember_theme.dart';

class AddHabitScreen extends ConsumerStatefulWidget {
  const AddHabitScreen({super.key, this.habit});
  final Habit? habit;

  @override
  ConsumerState<AddHabitScreen> createState() => _AddHabitScreenState();
}

class _AddHabitScreenState extends ConsumerState<AddHabitScreen> {
  final _name = TextEditingController();
  final _target = TextEditingController(text: '1');
  final _duration = TextEditingController(text: '30');
  String _icon = habitIcons.keys.first;
  Color _color = habitPalette.first;
  ScheduleType _schedule = ScheduleType.daily;
  HabitTaskType _taskType = HabitTaskType.normal;
  int _weekdayMask = Schedule.allDaysMask;
  int _timesPerWeek = 3;
  int _intervalDays = 2;
  int _periodTarget = 1;
  bool _twoDayRule = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    if (h == null) return;
    _name.text = h.name;
    _target.text = h.dailyTarget.toString();
    _duration.text = (h.targetDurationSeconds ~/ 60).toString();
    _icon = h.iconKey;
    _color = Color(h.colorValue);
    _schedule = ScheduleType.values[h.scheduleType];
    _taskType = HabitTaskType.values[h.taskType];
    _weekdayMask = h.weekdayMask;
    _timesPerWeek = h.timesPerWeek;
    _intervalDays = h.intervalDays;
    _periodTarget = h.periodTarget;
    _twoDayRule = h.twoDayRule;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _duration.dispose();
    super.dispose();
  }

  int _positive(TextEditingController c, int fallback, int max) {
    final value = int.tryParse(c.text) ?? fallback;
    return value.clamp(1, max);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your habit a name.')),
      );
      return;
    }
    if (_schedule == ScheduleType.weekdays && _weekdayMask == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one day.')),
      );
      return;
    }
    setState(() => _saving = true);
    final schedule = Schedule(
      type: _schedule,
      weekdayMask: _weekdayMask,
      timesPerWeek: _timesPerWeek,
      intervalDays: _intervalDays,
      periodTarget: _periodTarget,
      anchorDate: widget.habit?.createdAt ?? DateTime.now(),
    );
    final actions = ref.read(habitActionsProvider);
    if (widget.habit == null) {
      final existing = ref.read(habitsProvider).valueOrNull?.length ?? 0;
      await actions.add(
        name: name,
        iconKey: _icon,
        colorValue: _color.toARGB32(),
        schedule: schedule,
        dailyTarget: _positive(_target, 1, 999),
        sortOrder: existing,
        taskType: _taskType,
        twoDayRule: _twoDayRule,
        targetDurationSeconds: _positive(_duration, 30, 1440) * 60,
      );
    } else {
      await actions.edit(
        id: widget.habit!.id,
        name: name,
        iconKey: _icon,
        colorValue: _color.toARGB32(),
        schedule: schedule,
        dailyTarget: _positive(_target, 1, 999),
        taskType: _taskType,
        twoDayRule: _twoDayRule,
        targetDurationSeconds: _positive(_duration, 30, 1440) * 60,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.habit != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit habit' : 'New habit')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          TextField(
            controller: _name,
            autofocus: !editing,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Habit name'),
          ),
          const _Label('Task type'),
          DropdownButtonFormField<HabitTaskType>(
            initialValue: _taskType,
            items: const [
              DropdownMenuItem(value: HabitTaskType.normal, child: Text('Normal')),
              DropdownMenuItem(value: HabitTaskType.negative, child: Text('Negative / avoid')),
              DropdownMenuItem(value: HabitTaskType.timed, child: Text('Timed')),
            ],
            onChanged: (v) => setState(() => _taskType = v ?? _taskType),
          ),
          if (_taskType == HabitTaskType.negative) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Apply the 2-day rule'),
              subtitle: const Text('One missed scheduled period is allowed; two in a row break the streak.'),
              value: _twoDayRule,
              onChanged: (v) => setState(() => _twoDayRule = v),
            ),
          ],
          if (_taskType == HabitTaskType.timed) ...[
            const _Label('Daily time target'),
            TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: 'minutes'),
            ),
          ] else ...[
            const _Label('Daily completion target'),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: 'completions'),
            ),
          ],
          const _Label('Schedule'),
          DropdownButtonFormField<ScheduleType>(
            initialValue: _schedule,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: ScheduleType.daily, child: Text('Daily')),
              DropdownMenuItem(value: ScheduleType.weekdays, child: Text('Specific days')),
              DropdownMenuItem(value: ScheduleType.timesPerWeek, child: Text('N times per week')),
              DropdownMenuItem(value: ScheduleType.everyNDays, child: Text('Every N days')),
              DropdownMenuItem(value: ScheduleType.weekly, child: Text('Weekly goal')),
              DropdownMenuItem(value: ScheduleType.fortnightly, child: Text('Fortnightly goal')),
              DropdownMenuItem(value: ScheduleType.monthly, child: Text('Monthly goal')),
              DropdownMenuItem(value: ScheduleType.yearly, child: Text('Yearly goal')),
            ],
            onChanged: (v) => setState(() => _schedule = v ?? _schedule),
          ),
          if (_schedule == ScheduleType.weekdays) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(weekdayShortNames[i]),
                    selected: (_weekdayMask & (1 << i)) != 0,
                    onSelected: (on) => setState(() {
                      _weekdayMask = on
                          ? _weekdayMask | (1 << i)
                          : _weekdayMask & ~(1 << i);
                    }),
                  ),
              ],
            ),
          ],
          if (_schedule == ScheduleType.timesPerWeek)
            _NumberSetting(
              label: 'Completions per week',
              value: _timesPerWeek,
              min: 1,
              max: 7,
              onChanged: (v) => setState(() => _timesPerWeek = v),
            ),
          if (_schedule == ScheduleType.everyNDays)
            _NumberSetting(
              label: 'Repeat every N days',
              value: _intervalDays,
              min: 1,
              max: 365,
              onChanged: (v) => setState(() => _intervalDays = v),
            ),
          if ({
            ScheduleType.weekly,
            ScheduleType.fortnightly,
            ScheduleType.monthly,
            ScheduleType.yearly,
          }.contains(_schedule))
            _NumberSetting(
              label: 'Goal completions in this period',
              value: _periodTarget,
              min: 1,
              max: 366,
              onChanged: (v) => setState(() => _periodTarget = v),
            ),
          const _Label('Icon'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in habitIcons.entries)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _icon = entry.key),
                  child: CircleAvatar(
                    backgroundColor: _icon == entry.key
                        ? _color.withValues(alpha: .2)
                        : EmberColors.surface,
                    child: Icon(
                      entry.value,
                      color: _icon == entry.key ? _color : EmberColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const _Label('Colour'),
          Wrap(
            spacing: 12,
            children: [
              for (final c in habitPalette)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c ? EmberColors.text : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(editing ? 'Save changes' : 'Create habit'),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(
          value.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: EmberColors.textMuted,
                letterSpacing: 1.3,
              ),
        ),
      );
}

class _NumberSetting extends StatelessWidget {
  const _NumberSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$value'),
            IconButton(
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      );
}
