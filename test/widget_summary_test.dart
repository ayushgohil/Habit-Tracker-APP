import 'package:ember/core/widget_summary.dart';
import 'package:flutter_test/flutter_test.dart';

WidgetHabit h(String name, {bool done = false, int count = 0, int target = 1, bool timed = false}) =>
    WidgetHabit(name: name, done: done, count: count, target: target, timed: timed);

void main() {
  test('no habits says so', () {
    final s = buildWidgetSummary([]);
    expect(s.summary, 'No habits today');
    expect(s.rows, isEmpty);
  });

  test('counts finished habits and lists unfinished ones first', () {
    final s = buildWidgetSummary([h('Read', done: true), h('Run'), h('Write')]);
    expect(s.summary, '1 of 3 done');
    expect([for (final r in s.rows) r.text], ['○ Run', '○ Write', '✓ Read']);
    expect([for (final r in s.rows) r.done], [false, false, true]);
  });

  test('partial progress shows taps or minutes', () {
    final s = buildWidgetSummary([
      h('Water', count: 2, target: 8),
      h('Study', count: 1500, target: 3600, timed: true),
      h('Stretch', target: 3),
    ]);
    expect([for (final r in s.rows) r.text], ['○ Water  2/8', '○ Study  25/60 min', '○ Stretch']);
  });

  test('long lists are cut with a +N more row', () {
    final s = buildWidgetSummary([for (var i = 1; i <= 9; i++) h('Habit $i')], maxRows: 6);
    expect(s.rows, hasLength(6));
    expect(s.rows.last.text, '+4 more');
    expect(s.rows.first.text, '○ Habit 1');
    expect(s.summary, '0 of 9 done');
  });

  test('exactly maxRows habits are all shown', () {
    final s = buildWidgetSummary([for (var i = 1; i <= 6; i++) h('Habit $i')], maxRows: 6);
    expect(s.rows, hasLength(6));
    expect(s.rows.last.text, '○ Habit 6');
  });
}
