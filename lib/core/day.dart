/// Calendar-day helpers.
///
/// Days are identified by local-date strings (`yyyy-MM-dd`) so completions
/// never drift with timezones or daylight saving.
library;

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Monday-based start of the week containing [d].
DateTime startOfWeek(DateTime d) => addDays(startOfDay(d), -(d.weekday - 1));

String dayKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
