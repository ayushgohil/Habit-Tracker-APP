/// What the home-screen widget shows, worked out without any Flutter or
/// Android code so it can be tested.
library;

class WidgetHabit {
  const WidgetHabit({
    required this.name,
    required this.done,
    required this.count,
    required this.target,
    this.timed = false,
    this.id = 0,
    this.tappable = false,
  });
  final String name;
  final bool done;

  /// Progress today: taps, or seconds for a timed habit.
  final int count;
  final int target;
  final bool timed;
  final int id;

  /// True when one tap on the widget can log it (plain habits only; timed and
  /// Health Connect habits open the app instead).
  final bool tappable;
}

class WidgetRow {
  const WidgetRow(this.text, {required this.done, this.id = 0, this.tappable = false});
  final String text;
  final bool done;
  final int id;

  /// Tapping this row logs the habit from the widget. A finished habit is not
  /// tappable, so a stray touch cannot undo it.
  final bool tappable;
}

class WidgetSummary {
  const WidgetSummary({required this.summary, required this.rows});
  final String summary;
  final List<WidgetRow> rows;
}

/// Builds the widget's headline and rows. Unfinished habits come first, in
/// their own order, then finished ones. If there are more than [maxRows],
/// the last row says how many are not shown.
WidgetSummary buildWidgetSummary(List<WidgetHabit> habits, {int maxRows = 6}) {
  if (habits.isEmpty) {
    return const WidgetSummary(summary: 'No habits today', rows: []);
  }
  final done = habits.where((h) => h.done).length;
  final ordered = [
    ...habits.where((h) => !h.done),
    ...habits.where((h) => h.done),
  ];
  final visible = ordered.length > maxRows ? maxRows - 1 : ordered.length;
  final rows = <WidgetRow>[
    for (final h in ordered.take(visible)) WidgetRow(_rowText(h), done: h.done, id: h.id, tappable: h.tappable && !h.done),
  ];
  if (ordered.length > visible) {
    rows.add(WidgetRow('+${ordered.length - visible} more', done: false));
  }
  return WidgetSummary(summary: '$done of ${habits.length} done', rows: rows);
}

String _rowText(WidgetHabit h) {
  if (h.done) return '✓ ${h.name}';
  if (h.timed && h.count > 0) {
    return '○ ${h.name}  ${h.count ~/ 60}/${h.target ~/ 60} min';
  }
  if (!h.timed && h.target > 1 && h.count > 0) {
    return '○ ${h.name}  ${h.count}/${h.target}';
  }
  return '○ ${h.name}';
}
