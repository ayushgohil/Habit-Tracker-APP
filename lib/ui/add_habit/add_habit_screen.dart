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
import 'habit_created_screen.dart';
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

  /// Which step of the form is showing, and which way the last move went.
  int _stepIndex = 0;
  bool _forward = true;

  /// The name field takes focus only when the form first opens.
  bool _nameAutofocus = true;

  /// The first day the habit exists. Stored as the habit's creation date.
  DateTime _startDate = currentDay();

  /// The last day the habit is scheduled; null means it never ends.
  DateTime? _endDate;

  static const _stepNames = ['Basics', 'Goal', 'Schedule', 'Review'];

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    if (h == null) return;
    _nameAutofocus = false;
    _startDate = startOfDay(h.createdAt);
    _endDate = h.endDate == null ? null : startOfDay(h.endDate!);
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
    if (picked == null) return;
    setState(() {
      final end = _endDate;
      final newStart = startOfDay(picked);
      // Moving the start moves the end with it, so the habit keeps its length.
      if (end != null) _endDate = addDays(newStart, daysBetween(_startDate, end));
      _startDate = newStart;
    });
  }

  Future<void> _pickEndDate() async {
    final end = _endDate ?? addDays(_startDate, 29);
    final picked = await showDatePicker(
      context: context,
      initialDate: end.isBefore(_startDate) ? _startDate : end,
      firstDate: _startDate,
      lastDate: DateTime(_startDate.year + 5, _startDate.month, _startDate.day),
      helpText: 'Habit end date',
    );
    if (picked != null) setState(() => _endDate = startOfDay(picked));
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _goTo(int index) {
    final target = index.clamp(0, _stepNames.length - 1);
    if (target == _stepIndex) return;
    FocusScope.of(context).unfocus();
    setState(() {
      if (_stepIndex == 0) _nameAutofocus = false;
      _forward = target > _stepIndex;
      _stepIndex = target;
    });
  }

  bool get _weekdaysOk => _schedule != ScheduleType.weekdays || _weekdayMask != 0;

  /// Moves on from the current step once what it asks for is filled in.
  void _next() {
    if (_stepIndex == 0 && _name.text.trim().isEmpty) {
      _say('Give your habit a name.');
      return;
    }
    if (_stepIndex == 2 && !_weekdaysOk) {
      _say('Pick at least one day.');
      return;
    }
    _goTo(_stepIndex + 1);
  }

  Schedule get _scheduleValue => Schedule(
        type: _schedule,
        weekdayMask: _weekdayMask,
        timesPerWeek: _timesPerWeek,
        intervalDays: _intervalDays,
        periodTarget: _periodTarget,
        anchorDate: _startDate,
      );

  /// The goal in a few words, for the preview card.
  String _goalText() {
    String minutes(int m) {
      if (m < 60) return '$m min';
      return m % 60 == 0 ? '${m ~/ 60} hr' : '${m ~/ 60} hr ${m % 60} min';
    }

    if (_health != HealthMetric.none) return 'Health: ${_health.label}';
    switch (_taskType) {
      case HabitTaskType.timed:
        final m = _positive(_duration, 30, 1440);
        return _limit ? 'Under ${minutes(m)}' : minutes(m);
      case HabitTaskType.negative:
        return 'Avoid it';
      case HabitTaskType.normal:
        final t = _positive(_target, 1, _targetMax);
        final unit = _unit.text.trim();
        if (unit.isNotEmpty) return '$t $unit';
        return t == 1 ? 'Once' : '$t times';
    }
  }

  List<(IconData, String)> _summaryChips(BuildContext context) => [
        (Icons.flag_rounded, _goalText()),
        (Icons.repeat_rounded, _scheduleValue.describe()),
        if (dayKey(_startDate) != currentDayKey()) (Icons.event_rounded, 'Starts ${DateFormat('d MMM').format(_startDate)}'),
        if (_endDate != null) (Icons.event_busy_rounded, 'Ends ${DateFormat('d MMM').format(_endDate!)}'),
        if (_reminderEnabled) (Icons.notifications_active_rounded, _reminderTime.format(context)),
      ];

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
      _goTo(0);
      _say('Give your habit a name.');
      return;
    }
    if (!_weekdaysOk) {
      _goTo(2);
      _say('Pick at least one day.');
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      _goTo(2);
      _say('The end date must be on or after the start date.');
      return;
    }
    if (_linkValue == null) {
      _goTo(3);
      _say('That link does not look right. Try a web address like example.com.');
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
    final schedule = _scheduleValue;
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
        endDate: _endDate,
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
        endDate: _endDate,
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
    if (!mounted) return;
    if (old == null) {
      // A new habit gets a short celebration before landing on Home.
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => HabitCreatedScreen(
          name: name,
          iconKey: _icon,
          color: _color,
          scheduleText: schedule.describe(),
          startDate: _startDate,
          startsToday: dayKey(_startDate) == currentDayKey(),
        ),
      ));
    } else {
      Navigator.of(context).pop();
    }
  }

  static const _stepTitles = [
    'Name your habit',
    'Set the goal',
    'Choose a schedule',
    'Review and create',
  ];
  static const _stepHints = [
    'Pick something small and clear. You can change anything later.',
    'What counts as done?',
    'When does it repeat, and when should Ember remind you?',
    'Check how it looks, then create it.',
  ];

  static const _durationPresets = [5, 10, 15, 20, 30, 45, 60, 90];

  static const _scheduleChoices = <(ScheduleType, String, String)>[
    (ScheduleType.daily, 'Every day', 'Once a day, every day.'),
    (ScheduleType.weekdays, 'Specific days', 'Pick the weekdays it happens.'),
    (ScheduleType.timesPerWeek, 'Times per week', 'Any days you like, a set number each week.'),
    (ScheduleType.everyNDays, 'Every few days', 'A repeating gap, like every 3 days.'),
    (ScheduleType.weekly, 'Weekly goal', 'A number of completions each week.'),
    (ScheduleType.fortnightly, 'Fortnightly goal', 'A number of completions every two weeks.'),
    (ScheduleType.monthly, 'Monthly goal', 'A number of completions each month.'),
    (ScheduleType.yearly, 'Yearly goal', 'A number of completions each year.'),
  ];

  @override
  Widget build(BuildContext context) {
    final editing = widget.habit != null;
    final last = _stepIndex == _stepNames.length - 1;
    return PopScope(
      // While creating, Back goes to the previous step before it leaves.
      canPop: editing || _stepIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_stepIndex - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(editing ? 'Edit habit' : 'New habit'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: _StepTabs(labels: _stepNames, current: _stepIndex, color: _color, onTap: _goTo),
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: Offset(_forward ? .06 : -.06, 0), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(_stepIndex), child: _stepBody(context)),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                if (!editing && _stepIndex > 0) ...[
                  OutlinedButton(
                    key: const Key('step-back'),
                    onPressed: () => _goTo(_stepIndex - 1),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                      child: Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton(
                    key: const Key('primary-action'),
                    onPressed: _saving ? null : (editing || last ? _save : _next),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(editing ? 'Save changes' : (last ? 'Create habit' : 'Continue')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    final children = switch (_stepIndex) {
      0 => _basicsStep(context),
      1 => _goalStep(context),
      2 => _scheduleStep(context),
      _ => _reviewStep(context),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _StepHeading(title: _stepTitles[_stepIndex], hint: _stepHints[_stepIndex]),
        ...children,
      ],
    );
  }

  // ---- Step 1: name, look ---------------------------------------------------

  List<Widget> _basicsStep(BuildContext context) {
    final editing = widget.habit != null;
    return [
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        autofocus: _nameAutofocus,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Habit name'),
      ),
      const SizedBox(height: 4),
      _HabitPreview(
        key: const Key('habit-preview'),
        name: _name.text.trim(),
        iconKey: _icon,
        color: _color,
        chips: const [],
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
      const _Label('Icon'),
      IconPicker(selected: _icon, color: _color, onChanged: (key) => setState(() => _icon = key)),
      const _Label('Colour'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < habitPalette.length; i++)
            InkWell(
              key: Key('colour-$i'),
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _color = habitPalette[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: habitPalette[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color == habitPalette[i] ? EmberColors.text : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }

  // ---- Step 2: goal ---------------------------------------------------------

  static const _typeChoices = <(HabitTaskType, IconData, String, String)>[
    (HabitTaskType.normal, Icons.check_circle_outline_rounded, 'Do it', 'Tick it off, or count it: 8 glasses, 20 pages.'),
    (HabitTaskType.negative, Icons.block_rounded, 'Avoid it', 'Something to stay away from, like sugar or scrolling.'),
    (HabitTaskType.timed, Icons.timer_outlined, 'Timed', 'Track time with a timer. Set a goal or a limit.'),
  ];

  static String _presetLabel(int minutes) =>
      minutes >= 60 && minutes % 60 == 0 ? '${minutes ~/ 60} hr' : '$minutes min';

  List<Widget> _goalStep(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: EmberColors.textMuted);
    final fromHealth = _health != HealthMetric.none;
    final targetTitle = _taskType == HabitTaskType.timed
        ? (!fromHealth ? (_limit ? 'Daily time limit' : 'Daily time target') : _health.goalLabel)
        : (!fromHealth ? 'Daily completion target' : _health.goalLabel);
    return [
      const _Section(1, 'Type'),
      for (final (type, icon, title, subtitle) in _typeChoices)
        _ChoiceCard(
          key: Key('type-${type.name}'),
          icon: icon,
          title: title,
          subtitle: subtitle,
          selected: _taskType == type,
          color: _color,
          // A habit filled in from a health app has a fixed type.
          enabled: !fromHealth,
          onTap: () => setState(() => _taskType = type),
        ),
      if (fromHealth) Text('The type is set by the Health Connect source below.', style: muted),
      if (_taskType == HabitTaskType.negative)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Apply the 2-day rule'),
          subtitle: const Text('One missed scheduled period is allowed; two in a row break the streak.'),
          value: _twoDayRule,
          onChanged: (v) => setState(() => _twoDayRule = v),
        ),
      _Section(2, targetTitle),
      if (_taskType == HabitTaskType.timed) ...[
        if (!fromHealth)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final m in _durationPresets)
                ChoiceChip(
                  key: Key('preset-$m'),
                  label: Text(_presetLabel(m)),
                  selected: _positive(_duration, 30, 1440) == m,
                  onSelected: (_) => setState(() => _duration.text = '$m'),
                ),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(suffixText: 'minutes'),
        ),
        if (!fromHealth)
          SwitchListTile(
            key: const Key('limit-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep under this time'),
            subtitle: const Text('A limit, like 30 minutes of social media. The day stays done until the timer passes it.'),
            value: _limit,
            onChanged: (v) => setState(() => _limit = v),
          ),
        if (!fromHealth && !_limit) ...[
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
              child: Text(_sessionSummary(), key: const Key('session-summary'), style: muted),
            ),
        ],
      ] else ...[
        TextField(
          controller: _target,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            suffixText: fromHealth ? _health.goalUnit : (_unit.text.trim().isEmpty ? 'completions' : _unit.text.trim()),
          ),
        ),
        if (!fromHealth && _taskType != HabitTaskType.negative) ...[
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
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _writeHealth = on);
                if (on && !await healthWriter.requestWaterPermission() && mounted) {
                  setState(() => _writeHealth = false);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Health Connect did not allow writing water.')),
                  );
                }
              },
            ),
        ],
      ],
      const _Section(3, 'Fill in automatically', optional: true),
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
      if (fromHealth)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Ember reads this from Health Connect when you open the app. Tapping the habit refreshes it.',
            style: muted,
          ),
        ),
    ];
  }

  // ---- Step 3: schedule -----------------------------------------------------

  Widget _scheduleDetail(ScheduleType type) {
    switch (type) {
      case ScheduleType.daily:
        return const SizedBox.shrink();
      case ScheduleType.weekdays:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
                FilterChip(
                  label: Text(weekdayShortNames[i]),
                  selected: (_weekdayMask & (1 << i)) != 0,
                  onSelected: (on) => setState(() {
                    _weekdayMask = on ? _weekdayMask | (1 << i) : _weekdayMask & ~(1 << i);
                  }),
                ),
            ],
          ),
        );
      case ScheduleType.timesPerWeek:
        return _NumberSetting(
          label: 'Completions per week',
          value: _timesPerWeek,
          min: 1,
          max: 7,
          onChanged: (v) => setState(() => _timesPerWeek = v),
        );
      case ScheduleType.everyNDays:
        return _NumberSetting(
          label: 'Repeat every N days',
          value: _intervalDays,
          min: 1,
          max: 365,
          onChanged: (v) => setState(() => _intervalDays = v),
        );
      case ScheduleType.weekly:
      case ScheduleType.fortnightly:
      case ScheduleType.monthly:
      case ScheduleType.yearly:
        return _NumberSetting(
          label: 'Goal completions in this period',
          value: _periodTarget,
          min: 1,
          max: 366,
          onChanged: (v) => setState(() => _periodTarget = v),
        );
    }
  }

  List<Widget> _scheduleStep(BuildContext context) {
    final end = _endDate;
    return [
      const _Section(1, 'Repeat'),
      for (final (type, title, subtitle) in _scheduleChoices) ...[
        _ChoiceCard(
          key: Key('schedule-${type.name}'),
          icon: _scheduleIcon(type),
          title: title,
          subtitle: subtitle,
          selected: _schedule == type,
          color: _color,
          onTap: () => setState(() => _schedule = type),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _schedule == type ? _scheduleDetail(type) : const SizedBox(width: double.infinity),
        ),
      ],
      const _Section(2, 'Dates'),
      ListTile(
        key: const Key('start-date'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_rounded),
        title: Text(DateFormat('EEEE, d MMM yyyy').format(_startDate)),
        subtitle: const Text('Starts on. Pick an earlier day to log past days.'),
        onTap: _pickStartDate,
      ),
      SwitchListTile(
        key: const Key('end-date-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Set an end date'),
        subtitle: const Text('For a challenge or a short sprint. Your history stays after it ends.'),
        value: end != null,
        onChanged: (on) => setState(() => _endDate = on ? addDays(_startDate, 29) : null),
      ),
      if (end != null)
        ListTile(
          key: const Key('end-date'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_busy_rounded),
          title: Text(DateFormat('EEEE, d MMM yyyy').format(end)),
          subtitle: Text('Ends on. ${_lengthText(end)}'),
          onTap: _pickEndDate,
        ),
      const _Section(3, 'Reminders'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Daily reminder'),
        subtitle: const Text('Send a daily reminder at your chosen time'),
        value: _reminderEnabled,
        onChanged: (value) => setState(() => _reminderEnabled = value),
      ),
      if (_reminderEnabled) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reminder time'),
          subtitle: Text(_reminderTime.format(context)),
          trailing: const Icon(Icons.access_time_rounded),
          onTap: () => _pickReminderTime(nudge: false),
        ),
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Partial-progress nudge'),
          subtitle: const Text('Send a second reminder later in the day'),
          value: _partialNudgeEnabled,
          onChanged: (value) => setState(() => _partialNudgeEnabled = value),
        ),
        if (_partialNudgeEnabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Nudge time'),
            subtitle: Text(_partialNudgeTime.format(context)),
            trailing: const Icon(Icons.access_time_rounded),
            onTap: () => _pickReminderTime(nudge: true),
          ),
      ],
    ];
  }

  String _lengthText(DateTime end) {
    final days = daysBetween(_startDate, end) + 1;
    return days == 1 ? '1 day in total.' : '$days days in total.';
  }

  static IconData _scheduleIcon(ScheduleType type) {
    switch (type) {
      case ScheduleType.daily:
        return Icons.today_rounded;
      case ScheduleType.weekdays:
        return Icons.date_range_rounded;
      case ScheduleType.timesPerWeek:
        return Icons.view_week_rounded;
      case ScheduleType.everyNDays:
        return Icons.update_rounded;
      case ScheduleType.weekly:
      case ScheduleType.fortnightly:
      case ScheduleType.monthly:
      case ScheduleType.yearly:
        return Icons.flag_rounded;
    }
  }

  // ---- Step 4: review -------------------------------------------------------

  List<Widget> _reviewStep(BuildContext context) {
    return [
      const SizedBox(height: 16),
      _HabitPreview(
        key: const Key('habit-preview'),
        name: _name.text.trim(),
        iconKey: _icon,
        color: _color,
        chips: _summaryChips(context),
      ),
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
    ];
  }
}

/// A big title and one line of help at the top of each step.
class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(hint, style: textTheme.bodyMedium?.copyWith(color: EmberColors.textMuted)),
      ],
    );
  }
}

/// The step names under the app bar. Tap one to jump to it.
class _StepTabs extends StatelessWidget {
  const _StepTabs({required this.labels, required this.current, required this.color, required this.onTap});
  final List<String> labels;
  final int current;
  final Color color;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == current,
                button: true,
                child: InkWell(
                  key: Key('step-tab-$i'),
                  onTap: () => onTap(i),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            labels[i],
                            style: (i == current ? textTheme.titleSmall : textTheme.bodyMedium)?.copyWith(
                              color: i == current ? EmberColors.text : EmberColors.textMuted,
                              fontWeight: i == current ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        height: 3,
                        decoration: BoxDecoration(
                          color: i == current ? color : (i < current ? color.withValues(alpha: .4) : Colors.transparent),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A numbered section title, like "01  TYPE".
class _Section extends StatelessWidget {
  const _Section(this.number, this.title, {this.optional = false});
  final int number;
  final String title;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: EmberColors.track, width: 1.5),
            ),
            child: Text('0$number', style: textTheme.labelSmall?.copyWith(color: EmberColors.textMuted)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: textTheme.labelMedium?.copyWith(color: EmberColors.textMuted, letterSpacing: 1.3),
            ),
          ),
          if (optional) Text('Optional', style: textTheme.labelSmall?.copyWith(color: EmberColors.textMuted)),
        ],
      ),
    );
  }
}

/// A tappable card for choosing one of several options.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: EmberColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? color : Colors.transparent, width: 2),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, color: selected ? color : EmberColors.textMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(subtitle, style: textTheme.bodySmall?.copyWith(color: EmberColors.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? color : EmberColors.textMuted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How the habit will look, in its own colour. It follows the form as you type.
class _HabitPreview extends StatelessWidget {
  const _HabitPreview({super.key, required this.name, required this.iconKey, required this.color, required this.chips});
  final String name;
  final String iconKey;
  final Color color;
  final List<(IconData, String)> chips;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
    final on = dark ? Colors.white : const Color(0xFF1B1B1B);
    final textTheme = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, .22)!],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: on.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                child: Icon(habitIconFor(iconKey), color: on, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name.isEmpty ? 'Your habit' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge?.copyWith(color: on, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (icon, text) in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: on.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: on),
                        const SizedBox(width: 6),
                        Text(text, style: textTheme.labelMedium?.copyWith(color: on)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
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
