/// Works out which reminders to schedule, without any Android code so it can
/// be tested.
library;

import 'day.dart';
import 'streak.dart';

/// How many days ahead reminders are scheduled. They are topped up every time
/// the app opens or something changes.
const reminderHorizonDays = 10;

/// Which of a day's reminders this is: the main one, the second "nudge", or
/// one of up to [maxExtraReminders] extra times (for example other doses).
const mainSlot = 0;
const nudgeSlot = 1;
const firstExtraSlot = 2;
const maxExtraReminders = 4;
const _slotsPerDay = firstExtraSlot + maxExtraReminders;

class PlannedReminder {
  const PlannedReminder(this.when, {required this.slot});
  final DateTime when;
  final int slot;

  bool get nudge => slot == nudgeSlot;
  bool get extra => slot >= firstExtraSlot;

  @override
  String toString() => 'PlannedReminder($when, slot: $slot)';
}

/// Reads "08:00,14:30" into (hour, minute) pairs, ignoring anything invalid,
/// keeping at most [maxExtraReminders] distinct times in order.
List<(int, int)> parseExtraReminders(String text) {
  final out = <(int, int)>[];
  for (final part in text.split(',')) {
    final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(part);
    if (m == null) continue;
    final hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    if (hour > 23 || minute > 59 || out.contains((hour, minute))) continue;
    out.add((hour, minute));
    if (out.length == maxExtraReminders) break;
  }
  return out;
}

String formatExtraReminders(List<(int, int)> times) => [
      for (final t in times) '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}',
    ].join(',');

/// The reminders to schedule for one habit from [now] on.
///
/// - Only days the habit is due, and only from its start date.
/// - Nothing for today when the habit is already done today, so the reminder
///   never nags about something finished.
/// - Times that have already passed are skipped.
List<PlannedReminder> planReminders({
  required DateTime now,
  required Schedule schedule,
  required DateTime startDate,
  required int hour,
  required int minute,
  required bool nudgeEnabled,
  required int nudgeHour,
  required int nudgeMinute,
  required bool doneToday,
  List<(int, int)> extraTimes = const [],
  int days = reminderHorizonDays,
}) {
  final today = startOfDay(now);
  final out = <PlannedReminder>[];
  for (var i = 0; i < days; i++) {
    final day = addDays(today, i);
    if (!hasStartedBy(startDate, day) || !schedule.isDue(day)) continue;
    if (i == 0 && doneToday) continue;
    final main = DateTime(day.year, day.month, day.day, hour, minute);
    if (main.isAfter(now)) out.add(PlannedReminder(main, slot: mainSlot));
    if (nudgeEnabled) {
      final nudge = DateTime(day.year, day.month, day.day, nudgeHour, nudgeMinute);
      if (nudge.isAfter(now)) out.add(PlannedReminder(nudge, slot: nudgeSlot));
    }
    for (var e = 0; e < extraTimes.length && e < maxExtraReminders; e++) {
      final extra = DateTime(day.year, day.month, day.day, extraTimes[e].$1, extraTimes[e].$2);
      if (extra.isAfter(now)) out.add(PlannedReminder(extra, slot: firstExtraSlot + e));
    }
  }
  return out;
}

/// Notification ids for dated reminders: one block of 1000 per habit, six ids
/// (see the slots above) for each day of a 160-day cycle. Kept well away from
/// the older repeating ids and from timer ids.
int reminderNotificationId(int habitId, DateTime day, {required int slot}) {
  final epochDay = daysBetween(DateTime(1970), day);
  return reminderIdBase(habitId) + (epochDay % 160) * _slotsPerDay + slot;
}

int reminderIdBase(int habitId) => 2000000 + habitId * 1000;

bool isReminderIdOf(int id, int habitId) {
  final base = reminderIdBase(habitId);
  return id >= base && id < base + 1000;
}
