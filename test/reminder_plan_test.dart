import 'package:ember/core/reminder_plan.dart';
import 'package:ember/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final morning = DateTime(2026, 11, 20, 9, 0); // a Friday
  final start = DateTime(2026, 1, 1);

  List<PlannedReminder> plan({
    DateTime? now,
    Schedule schedule = const Schedule(),
    DateTime? startDate,
    bool nudge = false,
    bool done = false,
    int days = 3,
  }) =>
      planReminders(
        now: now ?? morning,
        schedule: schedule,
        startDate: startDate ?? start,
        hour: 20,
        minute: 0,
        nudgeEnabled: nudge,
        nudgeHour: 21,
        nudgeMinute: 30,
        doneToday: done,
        days: days,
      );

  test('a daily habit gets one reminder per day', () {
    expect(plan().map((r) => r.when), [
      DateTime(2026, 11, 20, 20),
      DateTime(2026, 11, 21, 20),
      DateTime(2026, 11, 22, 20),
    ]);
  });

  test('a habit finished today gets nothing for today but keeps tomorrow', () {
    expect(plan(done: true).map((r) => r.when), [
      DateTime(2026, 11, 21, 20),
      DateTime(2026, 11, 22, 20),
    ]);
  });

  test('a reminder time that has already passed today is skipped', () {
    final late = DateTime(2026, 11, 20, 20, 30);
    expect(plan(now: late).first.when, DateTime(2026, 11, 21, 20));
  });

  test('the second reminder is planned too, and skipped with the first when done', () {
    final both = plan(nudge: true, days: 1);
    expect(both.map((r) => r.nudge), [false, true]);
    expect(both.last.when, DateTime(2026, 11, 20, 21, 30));
    expect(plan(nudge: true, days: 1, done: true), isEmpty);
  });

  test('only the chosen weekdays get a reminder', () {
    // Mon and Sat only (bits 0 and 5).
    final days = plan(
      schedule: const Schedule(type: ScheduleType.weekdays, weekdayMask: 1 | 32),
      days: 7,
    ).map((r) => r.when.weekday);
    expect(days, [6, 1]); // Sat 21st, Mon 23rd... in date order
  });

  test('every-N-days habits only remind on their days', () {
    final reminders = plan(
      schedule: Schedule(type: ScheduleType.everyNDays, intervalDays: 3, anchorDate: DateTime(2026, 11, 20)),
      days: 7,
    );
    expect(reminders.map((r) => r.when.day), [20, 23, 26]);
  });

  test('nothing is planned before a future start date', () {
    final reminders = plan(startDate: DateTime(2026, 11, 22), days: 4);
    expect(reminders.map((r) => r.when.day), [22, 23]);
  });

  test('notification ids stay in the habit block and never repeat inside the horizon', () {
    final ids = <int>{};
    for (var i = 0; i < reminderHorizonDays; i++) {
      final day = DateTime(2026, 11, 20 + i);
      for (final nudge in [false, true]) {
        final id = reminderNotificationId(7, day, nudge: nudge);
        expect(isReminderIdOf(id, 7), isTrue);
        expect(isReminderIdOf(id, 8), isFalse);
        expect(ids.add(id), isTrue);
      }
    }
  });
}
