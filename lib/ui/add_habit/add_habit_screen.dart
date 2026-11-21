import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/day.dart';
import '../../core/habit_icons.dart';
import '../../core/health.dart';
import '../../core/reminder_plan.dart';
import '../../core/link.dart';
import '../../core/streak.dart';
import '../../health/health_writer.dart';
import '../../core/timer.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../health/health_sync.dart';
import '../../notifications/habit_notification_service.dart';
import '../../theme/ember_theme.dart';
import '../../core/habit_templates.dart';
import 'icon_picker.dart';

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
  final _session = TextEditingController();
  final _unit = TextEditingController();
  final _link = TextEditingController();
  bool _writeHealth = false;
  final _step = TextEditingController(text: '1');
  List<(int, int)> _extraTimes = [];
  String _icon = habitIconEntries.first.key;
  Color _color = habitPalette.first;
  ScheduleType _schedule = ScheduleType.daily;
  HabitTaskType _taskType = HabitTaskType.normal;
  HealthMetric _health = HealthMetric.none;
  int _weekdayMask = Schedule.allDaysMask;
  int _timesPerWeek = 3;
  int _intervalDays = 2;
  int _periodTarget = 1;
  bool _twoDayRule = false;
  bool _limit = false;
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 20, minute: 0);
  bool _partialNudgeEnabled = false;
  TimeOfDay _partialNudgeTime = const TimeOfDay(hour: 21, minute: 0);
  bool _saving = false;

  /// The first day the habit exists. Stored as the habit's creation date.
  DateTime _startDate = currentDay();

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    if (h == null) return;
    _startDate = startOfDay(h.createdAt);
    _name.text = h.name;
    _target.text = h.dailyTarget.toString();
    _unit.text = h.unitLabel;
    _link.text = h.linkUrl;
    _writeHealth = h.writeToHealth;
    _step.text = h.stepSize.toString();
    _extraTimes = parseExtraReminders(h.extraReminders);
    _duration.text = (h.targetDurationSeconds ~/ 60).toString();
    if (h.sessionSeconds > 0) _session.text = (h.sessionSeconds ~/ 60).toString();
    _icon = h.iconKey;
    _color = Color(h.colorValue);
    _schedule = ScheduleType.values[h.scheduleType];
    _taskType = HabitTaskType.values[h.taskType];
    _limit = h.limitMode;
    _health = HealthMetric.fromIndex(h.healthMetric);
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
    _session.dispose();
    _unit.dispose();
    _link.dispose();
    _step.dispose();
    super.dispose();
  }

  /// Step goals are in the thousands; other counts stay small.
  int get _targetMax => _health == HealthMetric.steps ? 200000 : (_unit.text.trim().isNotEmpty ? 100000 : 999);

  /// Fills the form from a ready-made habit. Everything stays editable.
  Future<void> _applyTemplate(HabitTemplate t) async {
    setState(() {
      _name.text = t.name;
      _icon = t.iconKey;
      _color = t.color;
      _taskType = t.taskType;
      _twoDayRule = false;
      _limit = false;
      _writeHealth = false;
      _health = HealthMetric.none;
      _unit.text = t.unit;
      _step.text = '${t.step}';
      _session.text = t.sessionMinutes > 0 ? '${t.sessionMinutes}' : '';
      if (t.taskType == HabitTaskType.timed) {
        _duration.text = '${t.target}';
      } else {
        _target.text = '${t.target}';
      }
    });
    if (t.health != HealthMetric.none) {
      await _pickHealth(t.health);
      if (!mounted) return;
      setState(() {
        if (t.taskType == HabitTaskType.timed) {
          _duration.text = '${t.target}';
        } else {
          _target.text = '${t.target}';
        }
      });
    }
  }

  /// What is saved for the unit, step and extra reminder times. Negative and
  /// timed habits, and ones filled in from Health Connect, keep the defaults.
  bool get _countsInUnits =>
      _health == HealthMetric.none && _taskType == HabitTaskType.normal;
  /// The link to save: cleaned up, or '' for none. Null when what was typed is not a link.
  String? get _linkValue => normalizeLink(_link.text);

  /// Water in millilitres can also be written to Health Connect.
  bool get _writeHealthValue => _countsInUnits && countsInMillilitres(_unit.text) && _writeHealth;
  String get _unitValue => _countsInUnits ? _unit.text.trim() : '';
  int get _stepValue => _countsInUnits ? _positive(_step, 1, _targetMax) : 1;
  /// A limit ("stay under") only makes sense for a plain timed habit.
  bool get _limitValue => _taskType == HabitTaskType.timed && _health == HealthMetric.none && _limit;

  /// Seconds per session for a timed habit, or 0 when it is one session.
  int get _sessionValue {
    if (_taskType != HabitTaskType.timed || _health != HealthMetric.none || _limit) return 0;
    final minutes = int.tryParse(_session.text.trim()) ?? 0;
    return normalizeSessionSeconds(_positive(_duration, 30, 1440) * 60, minutes * 60);
  }

  String get _extraValue => _reminderEnabled ? formatExtraReminders(_extraTimes) : '';

  String _sessionSummary() {
    final plan = SessionPlan(
      goalSeconds: _positive(_duration, 30, 1440) * 60,
      sessionSeconds: _sessionValue,
    );
    final minutes = plan.sessionSeconds ~/ 60;
    return '${plan.count} sessions of $minutes min. You get an alert as each one ends.';
  }

  Future<void> _addExtraTime() async {
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 12, minute: 0));
    if (picked == null || !mounted) return;
    final time = (picked.hour, picked.minute);
    if (_extraTimes.contains(time) || _extraTimes.length >= maxExtraReminders) return;
    setState(() => _extraTimes = [..._extraTimes, time]..sort((a, b) => (a.$1 * 60 + a.$2).compareTo(b.$1 * 60 + b.$2)));
  }

  Future<void> _pickHealth(HealthMetric metric) async {
    setState(() {
      _health = metric;
      if (metric != HealthMetric.none) {
        _taskType = metric.taskType;
        if (metric == HealthMetric.steps && (int.tryParse(_target.text) ?? 1) < 100) _target.text = '8000';
        if (metric == HealthMetric.exercise) _duration.text = '30';
        if (metric == HealthMetric.sleep) _duration.text = '480';
      }
    });
    if (metric == HealthMetric.none) return;
    final granted = await ref.read(healthSourceProvider).requestPermission(metric);
    if (!mounted || granted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ember can\'t read Health Connect yet. Install or open Health Connect and allow access, then edit this habit again.')),
    );
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
    final now = currentDay();
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
    if (_linkValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That link does not look right. Try a web address like example.com.')),
      );
      return;
    }
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
        : _positive(_target, 1, _targetMax);
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
        dailyTarget: _positive(_target, 1, _targetMax),
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
        healthMetric: _health.index,
        unitLabel: _unitValue,
        stepSize: _stepValue,
        extraReminders: _extraValue,
        sessionSeconds: _sessionValue,
        limitMode: _limitValue,
        linkUrl: _linkValue ?? '',
        writeToHealth: _writeHealthValue,
      );
    } else {
      savedHabitId = widget.habit!.id;
      await actions.edit(
        id: widget.habit!.id,
        name: name,
        iconKey: _icon,
        colorValue: _color.toARGB32(),
        schedule: schedule,
        dailyTarget: _positive(_target, 1, _targetMax),
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
        healthMetric: _health.index,
        unitLabel: _unitValue,
        stepSize: _stepValue,
        extraReminders: _extraValue,
        sessionSeconds: _sessionValue,
        limitMode: _limitValue,
        linkUrl: _linkValue ?? '',
        writeToHealth: _writeHealthValue,
      );
    }
    final db = ref.read(databaseProvider);
    final savedHabit = await (db.select(db.habits)
          ..where((row) => row.id.equals(savedHabitId)))
        .getSingle();
    await HabitNotificationService.instance.syncHabit(savedHabit);
    if (_health != HealthMetric.none) {
      // Fill in today from Health Connect right away; never blocks saving.
      ref.read(healthSyncProvider).syncNow();
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
          if (!editing) ...[
            const _Label('Quick start'),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: habitTemplates.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final t = habitTemplates[i];
                  return ActionChip(
                    key: Key('template-${t.id}'),
                    avatar: Icon(habitIconFor(t.iconKey), size: 18, color: t.color),
                    label: Text(t.name),
                    onPressed: () => _applyTemplate(t),
                  );
                },
              ),
            ),
          ],
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
            // A habit filled in from a health app has a fixed type.
            onChanged: _health == HealthMetric.none ? (v) => setState(() => _taskType = v ?? _taskType) : null,
          ),
          const _Label('Fill in automatically'),
          DropdownButtonFormField<HealthMetric>(
            key: const Key('health-metric'),
            isExpanded: true,
            initialValue: _health,
            items: [
              for (final m in HealthMetric.values)
                DropdownMenuItem(
                  value: m,
                  child: Text(
                    m == HealthMetric.none ? 'No, I will log it myself' : 'From Health Connect: ${m.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => _pickHealth(v ?? _health),
          ),
          if (_health != HealthMetric.none)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Ember reads this from Health Connect when you open the app. Tapping the habit refreshes it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: EmberColors.textMuted),
              ),
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
            _Label(_health == HealthMetric.none ? (_limit ? 'Daily time limit' : 'Daily time target') : _health.goalLabel),
            TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(suffixText: 'minutes'),
            ),
            if (_health == HealthMetric.none)
              SwitchListTile(
                key: const Key('limit-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep under this time'),
                subtitle: const Text('A limit, like 30 minutes of social media. The day stays done until the timer passes it.'),
                value: _limit,
                onChanged: (v) => setState(() => _limit = v),
              ),
            if (_health == HealthMetric.none && !_limit) ...[
              const _Label('Split into sessions (optional)'),
              TextField(
                key: const Key('session-field'),
                controller: _session,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  suffixText: 'minutes each',
                  hintText: 'e.g. 25 for focus rounds',
                ),
              ),
              if (_sessionValue > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _sessionSummary(),
                    key: const Key('session-summary'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: EmberColors.textMuted),
                  ),
                ),
            ],
          ] else ...[
            _Label(_health == HealthMetric.none ? 'Daily completion target' : _health.goalLabel),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                suffixText: _health != HealthMetric.none
                    ? _health.goalUnit
                    : (_unit.text.trim().isEmpty ? 'completions' : _unit.text.trim()),
              ),
            ),
            if (_health == HealthMetric.none && _taskType != HabitTaskType.negative) ...[
              const _Label('Counted in (optional)'),
              TextField(
                key: const Key('unit-field'),
                controller: _unit,
                maxLength: 12,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'ml, pages, doses...', counterText: ''),
              ),
              const _Label('Each tap adds'),
              TextField(
                key: const Key('step-field'),
                controller: _step,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(suffixText: _unit.text.trim().isEmpty ? null : _unit.text.trim()),
              ),
              if (countsInMillilitres(_unit.text))
                SwitchListTile(
                  key: const Key('health-write-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Save to Health Connect'),
                  subtitle: const Text('Adds each drink you log to Health Connect as water'),
                  value: _writeHealth,
                  onChanged: (on) async {
                    setState(() => _writeHealth = on);
                    if (on && !await healthWriter.requestWaterPermission() && mounted) {
                      setState(() => _writeHealth = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Health Connect did not allow writing water.')),
                      );
                    }
                  },
                ),
            ],
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
          if (_reminderEnabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final t in _extraTimes)
                    InputChip(
                      key: Key('extra-${t.$1}-${t.$2}'),
                      label: Text(TimeOfDay(hour: t.$1, minute: t.$2).format(context)),
                      onDeleted: () => setState(() => _extraTimes = [for (final e in _extraTimes) if (e != t) e]),
                    ),
                  if (_extraTimes.length < maxExtraReminders)
                    ActionChip(
                      key: const Key('add-extra-time'),
                      avatar: const Icon(Icons.add_alarm_rounded, size: 18),
                      label: Text(_extraTimes.isEmpty ? 'Add another time (other doses)' : 'Add another time'),
                      onPressed: _addExtraTime,
                    ),
                ],
              ),
            ),
          if (_reminderEnabled) ...[
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Partial-progress nudge'),
              subtitle: const Text('Send a second reminder later in the day'),
              value: _partialNudgeEnabled, onChanged: (value) => setState(() => _partialNudgeEnabled = value)),
            if (_partialNudgeEnabled)
              ListTile(contentPadding: EdgeInsets.zero, title: const Text('Nudge time'),
                subtitle: Text(_partialNudgeTime.format(context)), trailing: const Icon(Icons.access_time_rounded),
                onTap: () => _pickReminderTime(nudge: true)),
          ],
          const _Label('Link (optional)'),
          TextField(
            key: const Key('link-field'),
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'example.com or an app link',
              helperText: 'Adds an "Open link" button to the habit, for a website or an app.',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const _Label('Icon'),
          IconPicker(selected: _icon, color: _color, onChanged: (key) => setState(() => _icon = key)),
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
