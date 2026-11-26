import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/habit_templates.dart';
import 'package:ember/data/backup.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:ember/ui/notes/notes_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'add_habit_helpers.dart';
import 'home_flow_test.dart' show settle;

DayNote note(String day, String text, {bool pinned = false}) => DayNote(day: day, note: text, pinned: pinned);

void main() {
  test('notes are searched by text and date, pinned first, newest first', () {
    final notes = [
      note('2026-03-01', 'Went for a long run'),
      note('2026-03-05', 'Felt tired, skipped the gym'),
      note('2026-02-10', 'Great run by the lake', pinned: true),
    ];
    expect(filterNotes(notes, '').map((n) => n.day), ['2026-02-10', '2026-03-05', '2026-03-01']);
    expect(filterNotes(notes, 'run').map((n) => n.day), ['2026-02-10', '2026-03-01']);
    expect(filterNotes(notes, 'RUN lake').map((n) => n.day), ['2026-02-10']);
    expect(filterNotes(notes, 'march').map((n) => n.day), ['2026-03-05', '2026-03-01']);
    expect(filterNotes(notes, 'nothing here'), isEmpty);
  });

  test('template ids are unique and every icon exists', () {
    expect(habitTemplates.map((t) => t.id).toSet().length, habitTemplates.length);
    for (final t in habitTemplates) {
      expect(t.target, greaterThan(0));
    }
  });

  test('pinning keeps the text, editing keeps the pin, and backups round-trip it', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.setDayNote(day: '2026-03-01', note: 'first');
    await db.setNotePinned(day: '2026-03-01', pinned: true);
    await db.setDayNote(day: '2026-03-01', note: 'edited');
    var rows = await db.select(db.dayNotes).get();
    expect(rows.single.note, 'edited');
    expect(rows.single.pinned, isTrue);

    final json = await exportBackupJson(db);
    await db.setNotePinned(day: '2026-03-01', pinned: false);
    await restoreBackupJson(db, json);
    rows = await db.select(db.dayNotes).get();
    expect(rows.single.pinned, isTrue);
  });

  testWidgets('the notes screen lists, filters and pins notes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.setDayNote(day: '2026-03-01', note: 'Went for a long run');
      await db.setDayNote(day: '2026-03-05', note: 'Skipped the gym');
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const EmberApp(),
    ));
    await settle(tester);

    await tester.tap(find.byKey(const Key('notes-button')));
    await settle(tester);
    expect(find.text('Went for a long run'), findsOneWidget);
    expect(find.text('Skipped the gym'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('notes-search')), 'gym');
    await tester.pump();
    expect(find.text('Went for a long run'), findsNothing);
    expect(find.text('Skipped the gym'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('notes-search')), '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('pin-2026-03-01')));
    await settle(tester);
    final rows = await tester.runAsync(() => db.select(db.dayNotes).get());
    expect(rows!.firstWhere((n) => n.day == '2026-03-01').pinned, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });

  testWidgets('a quick-start suggestion fills in the new habit form', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 3000);
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const EmberApp(),
    ));
    await settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.byKey(const Key('template-water')));
    await settle(tester);
    expect(find.widgetWithText(TextField, 'Drink water'), findsOneWidget);
    await openStep(tester, 1);
    expect(find.widgetWithText(TextField, '2000'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'ml'), findsWidgets);

    await openStep(tester, 0);
    await tester.tap(find.byKey(const Key('template-read')));
    await settle(tester);
    expect(find.widgetWithText(TextField, 'Read'), findsOneWidget);
    await openStep(tester, 1);
    expect(find.widgetWithText(TextField, '20'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}
