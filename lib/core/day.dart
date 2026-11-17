/// Calendar-day helpers.
///
/// Days are identified by local-date strings (`yyyy-MM-dd`) so completions
/// never drift with timezones or daylight saving.
library;

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Whole calendar days from [from] to [to], ignoring time of day.
///
/// Computed in UTC so a daylight-saving change between the two dates can't
/// shave an hour off the difference and make `inDays` come out one short.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
      to.year,
      to.month,
      to.day,
    ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Whether a habit that starts on [start] already exists on [day].
///
/// A habit is not shown (and does not count) on days before it started.
bool hasStartedBy(DateTime start, DateTime day) =>
    !startOfDay(start).isAfter(startOfDay(day));

/// Monday-based start of the week containing [d].
DateTime startOfWeek(DateTime d) => addDays(startOfDay(d), -(d.weekday - 1));

String dayKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
