# Ember habit engine — Phase 1

## Habit lifecycle

- Active habits can be edited and reordered without changing their completion history.
- Paused habits are hidden from the daily dashboard but remain available in the Habit Library.
- Archived habits are hidden from the dashboard and can be restored from the Habit Library.
- Deleting a habit remains destructive and removes its completion rows.

## Task types

- **Normal:** progress is recorded as a count against the configured daily target.
- **Negative:** a completed period represents successfully avoiding the unwanted behaviour. The optional two-day rule tolerates one missed scheduled period; two consecutive missed periods end the streak.
- **Timed:** users record completed minutes; progress is persisted as seconds against the configured duration target.

## Schedule semantics

- **Daily:** one completion is expected on each calendar day.
- **Specific days:** one completion is expected on each selected weekday. Unselected weekdays are excluded from streak and completion-rate calculations.
- **N times per week:** the weekly target is evaluated in Monday-to-Sunday weeks.
- **Every N days:** intervals are anchored to the habit creation date.
- **Weekly:** the configured target is evaluated in Monday-to-Sunday weeks.
- **Fortnightly:** the configured target is evaluated in consecutive 14-day periods anchored to Monday, 5 January 1970.
- **Monthly:** the configured target is evaluated in calendar months.
- **Yearly:** the configured target is evaluated in calendar years.

The current period remains open and does not break the current streak before it ends. Completion rate is completed periods divided by elapsed periods, including the currently open period.

## Persistence

Schema version 2 adds task type, the negative-habit grace-rule flag, interval and period targets, timed target seconds, and pause timestamp. Existing schedule enum values retain their original numeric indexes, so existing rows keep their meaning during migration.

## Tests

The streak unit tests cover daily, selected weekdays, N-per-week, every-N-days, weekly, fortnightly, monthly, and yearly schedules, plus the negative-habit two-day rule and completion statistics. GitHub Actions runs static analysis and unit tests before building both APK variants.
