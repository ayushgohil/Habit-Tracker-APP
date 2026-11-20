/// Works out which reminders to schedule, without any Android code so it can
/// be tested.
library;

import 'day.dart';
import 'streak.dart';

/// How many days ahead reminders are scheduled. They are topped up every time
/// the app opens or something changes.
const reminderHorizonDays = 10;

class PlannedReminder {
  const PlannedReminder(this.when, {required this.nudge});
  final DateTime when;
  final bool nudge;

  @override
  String toString() => 'PlannedReminder($when, nudge: $nudge)';
}

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
  int days = reminderHorizonDays,
}) {
  final today = startOfDay(now);
  final out = <PlannedReminder>[];
  for (var i = 0; i < days; i++) {
    final day = addDays(today, i);
    if (!hasStartedBy(startDate, day) || !schedule.isDue(day)) continue;
    if (i == 0 && doneToday) continue;
    final main = DateTime(day.year, day.month, day.day, hour, minute);
    if (main.isAfter(now)) out.add(PlannedReminder(main, nudge: false));
    if (nudgeEnabled) {
      final nudge = DateTime(day.year, day.month, day.day, nudgeHour, nudgeMinute);
      if (nudge.isAfter(now)) out.add(PlannedReminder(nudge, nudge: true));
    }
  }
  return out;
}

/// Notification ids for dated reminders: one block of 1000 per habit, two ids
/// (reminder, nudge) for each day of a 500-day cycle. Kept well away from the
/// older repeating ids and from timer ids.
int reminderNotificationId(int habitId, DateTime day, {required bool nudge}) {
  final epochDay = daysBetween(DateTime(1970), day);
  return reminderIdBase(habitId) + (epochDay % 500) * 2 + (nudge ? 1 : 0);
}

int reminderIdBase(int habitId) => 2000000 + habitId * 1000;

bool isReminderIdOf(int id, int habitId) {
  final base = reminderIdBase(habitId);
  return id >= base && id < base + 1000;
}
