import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_flow_test.dart' show settle;

/// Moves through the steps of the add-habit screen, creates the habit and
/// closes the "Habit created!" screen.
Future<void> createHabit(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.tap(find.byKey(const Key('primary-action')));
    await settle(tester);
    if (find.byKey(const Key('celebration-done')).evaluate().isNotEmpty) break;
  }
  await tester.tap(find.byKey(const Key('celebration-done')));
  await settle(tester);
}

/// Opens one of the steps (0 Basics, 1 Goal, 2 Schedule, 3 Review).
Future<void> openStep(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(Key('step-tab-$index')));
  await settle(tester);
}
