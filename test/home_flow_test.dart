import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Lets real async work (the in-memory database) run, then redraws.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create a habit, open its menu, pause it and resume it', (
    tester,
  ) async {
    // A typical phone: 411 x 800 logical pixels.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const EmberApp(),
      ),
    );
    await settle(tester);
    expect(find.text('Light your first ember'), findsOneWidget);

    // Create a habit through the form.
    await tester.tap(find.text('Add a habit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'DSA learning');
    await tester.tap(find.text('Create habit'));
    await settle(tester);
    expect(find.text('DSA learning'), findsWidgets);

    // Open the habit menu. It must fit without overflowing.
    await tester.longPress(find.text('DSA learning').last);
    await tester.pumpAndSettle();
    expect(find.text('Edit habit'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Delete'),
      100,
      scrollable: find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(find.text('Delete'), findsOneWidget);

    // Pause it from the menu.
    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect(find.text('Light your first ember'), findsOneWidget);

    // Bring it back from the habit library.
    await tester.tap(find.byTooltip('Habit library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paused'));
    await tester.pumpAndSettle();
    expect(find.text('DSA learning'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await settle(tester);
    expect(find.text('No paused habits'), findsOneWidget);

    // Leave the library; the habit is back on the home screen.
    await tester.pageBack();
    await settle(tester);
    expect(find.text('DSA learning'), findsWidgets);

    // Tear down before closing the database.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
    await tester.pump(const Duration(seconds: 1));
  });
}
