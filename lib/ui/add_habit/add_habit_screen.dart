import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/day.dart';
import '../../core/habit_icons.dart';
import '../../core/streak.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../notifications/habit_notification_service.dart';
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
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 20, minute: 0);
  bool _partialNudgeEnabled = false;
  TimeOfDay _partialNudgeTime = const TimeOfDay(hour: 21, minute: 0);
  bool _saving = false;

  /// The first day the habit exists. Stored as the habit's creation date.
  DateTime _startDate = startOfDay(DateTime.now());

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    if (h == null) return;
    _startDate = startOfDay(h.createdAt);
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
    _reminderEnabled = h.reminderEnabled;
    _reminderTime = TimeOfDay(hour: h.reminderHour, minute: h.reminderMinute);
    _partialNudgeEnabled = h.partialNudgeEnabled;
    _partialNudgeTime = TimeOfDay(hour: h.partialNudgeHour, minute: h.partialNudgeMinute);
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

  Future<void> _pickReminderTime({required bool nudge}) async {
    final picked = await showTimePicker(context: context, initialTime: nudge ? _partialNudgeTime : _reminderTime);
    if (picked == null || !mounted) return;
    setState(() {
      if (nudge) { _partialNudgeTime = picked; } else { _reminderTime = picked; }
    });
  }

  Future<void> _pickStartDate() async {
    final now = startOfDay(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'Habit start date',
    );
    if (picked != null) setState(() => _startDate = startOfDay(picked));
  }

  Future<bool?> _confirm({required String title, required String message, required String action}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(action)),
        ],
      ),
    );
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
    if (_reminderEnabled) {
      final granted = await HabitNotificationService.instance.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allow notifications in Android settings to receive habit reminders.')),
        );
      }
    }
    final schedule = Schedule(
      type: _schedule,
      weekdayMask: _weekdayMask,
      timesPerWeek: _timesPerWeek,
      intervalDays: _intervalDays,
      periodTarget: _periodTarget,
      anchorDate: _startDate,
    );
    final newTarget = _taskType == HabitTaskType.timed
        ? _positive(_duration, 30, 1440) * 60
        : _positive(_target, 1, 999);
    var wholeHistory = false;
    final old = widget.habit;
    if (old != null) {
      if (dayKey(_startDate) != dayKey(old.createdAt)) {
        final ok = await _confirm(
          title: 'Change the start date?',
          message: 'Days before the new start date stop counting towards this habit, and days since an earlier start count as missed. Nothing you logged is deleted.',
          action: 'Change it',
        );
        if (ok != true || !mounted) return;
      }
      final goalChanged = old.taskType != _taskType.index ||
          (old.taskType == HabitTaskType.timed.index ? old.targetDurationSeconds : old.dailyTarget) != newTarget ||
          old.scheduleType != schedule.type.index ||
          old.weekdayMask != schedule.weekdayMask ||
          old.timesPerWeek != schedule.timesPerWeek ||
          old.intervalDays != schedule.intervalDays ||
          old.periodTarget != schedule.periodTarget;
      if (goalChanged) {
        if (!mounted) return;
        final choice = await showDialog<_GoalChange>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Apply the new goal from when?'),
            content: const Text('Past days can keep the goal they had, so your streak and history stay as they were, or everything can be judged against the new goal.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(_GoalChange.cancel), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(_GoalChange.allDays), child: const Text('All past days')),
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(_GoalChange.fromToday), child: const Text('From today')),
            ],
          ),
        );
        if (choice == null || choice == _GoalChange.cancel || !mounted) return;
        wholeHistory = choice == _GoalChange.allDays;
      }
    }
    setState(() => _saving = true);
    final actions = ref.read(habitActionsProvider);
    late final int savedHabitId;
    if (widget.habit == null) {
      final existing = ref.read(habitsProvider).valueOrNull?.length ?? 0;
      savedHabitId = await actions.add(
        name: name,
        iconKey: _icon,
        colorValue: _color.toARGB32(),
        schedule: schedule,
        dailyTarget: _positive(_target, 1, 999),
        sortOrder: existing,
        taskType: _taskType,
        twoDayRule: _twoDayRule,
        targetDurationSeconds: _positive(_duration, 30, 1440) * 60,
        reminderEnabled: _reminderEnabled,
        reminderHour: _reminderTime.hour,
        reminderMinute: _reminderTime.minute,
        partialNudgeEnabled: _partialNudgeEnabled,
        partialNudgeHour: _partialNudgeTime.hour,
        partialNudgeMinute: _partialNudgeTime.minute,
        startDate: _startDate,
      );
    } else {
      savedHabitId = widget.habit!.id;
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
        reminderEnabled: _reminderEnabled,
        reminderHour: _reminderTime.hour,
        reminderMinute: _reminderTime.minute,
        partialNudgeEnabled: _partialNudgeEnabled,
        partialNudgeHour: _partialNudgeTime.hour,
        partialNudgeMinute: _partialNudgeTime.minute,
        startDate: _startDate,
        applyToWholeHistory: wholeHistory,
      );
    }
    final db = ref.read(databaseProvider);
    final savedHabit = await (db.select(db.habits)
          ..where((row) => row.id.equals(savedHabitId)))
        .getSingle();
    await HabitNotificationService.instance.syncHabit(savedHabit);
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
          const _Label('Starts on'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: Text(DateFormat('EEEE, d MMM yyyy').format(_startDate)),
            subtitle: const Text('Shown from this day on. Pick an earlier day to log past days.'),
            onTap: _pickStartDate,
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
          const _Label('Reminders'),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Daily reminder'),
            subtitle: const Text('Send a daily reminder at your chosen time'),
            value: _reminderEnabled, onChanged: (value) => setState(() => _reminderEnabled = value)),
          if (_reminderEnabled)
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('Reminder time'),
              subtitle: Text(_reminderTime.format(context)), trailing: const Icon(Icons.access_time_rounded),
              onTap: () => _pickReminderTime(nudge: false)),
          if (_reminderEnabled) ...[
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Partial-progress nudge'),
              subtitle: const Text('Send a second reminder later in the day'),
              value: _partialNudgeEnabled, onChanged: (value) => setState(() => _partialNudgeEnabled = value)),
            if (_partialNudgeEnabled)
              ListTile(contentPadding: EdgeInsets.zero, title: const Text('Nudge time'),
                subtitle: Text(_partialNudgeTime.format(context)), trailing: const Icon(Icons.access_time_rounded),
                onTap: () => _pickReminderTime(nudge: true)),
          ],
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

enum _GoalChange { cancel, fromToday, allDays }
