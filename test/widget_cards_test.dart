import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/streak.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:ember/widgets/card_data.dart';
import 'package:ember/widgets/card_painter.dart';
import 'package:ember/widgets/widget_cards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  // A Wednesday, so the week has days behind and ahead of it.
  final today = DateTime(2026, 11, 18);
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> habit({int target = 1, int type = 0, DateTime? created}) => db.insertHabit(HabitsCompanion.insert(
        name: 'Read',
        iconKey: 'book',
        colorValue: 0xFF5E9BFF,
        taskType: Value(type),
        dailyTarget: Value(target),
        createdAt: Value(created ?? DateTime(2026, 11, 1)),
      ));

  Future<CardHabit> card(int id) async {
    final view = (await loadViewsOn(db, today)).firstWhere((v) => v.habit.id == id);
    final history = (await loadHistoriesOn(db, today)).firstWhere((h) => h.habit.id == id);
    return buildCardHabit(view, history, today);
  }

  test('the week card covers Monday to Sunday and leaves days ahead empty', () async {
    final id = await habit(target: 2);
    await db.setCompletion(habitId: id, day: '2026-11-16', amount: 2); // Mon, done
    await db.setCompletion(habitId: id, day: '2026-11-17', amount: 1); // Tue, half
    final c = await card(id);
    expect(c.week, [1.0, 0.5, 0.0, null, null, null, null]);
  });

  test('the trend card is the last 30 days ending today', () async {
    final id = await habit();
    await db.setCompletion(habitId: id, day: '2026-11-18', amount: 1);
    final c = await card(id);
    expect(c.trend.length, trendDays);
    expect(c.trend.last, 1.0);
    expect(c.trend.first, 0.0);
    expect(c.trendFrom, '20 Oct 26');
  });

  test('the month card lays out November 2026 in Monday-first weeks', () async {
    final id = await habit();
    await db.setCompletion(habitId: id, day: '2026-11-03', amount: 1);
    final c = await card(id);
    // 1 Nov 2026 is a Sunday: six blanks, then the 1st in the last column.
    expect(c.month.length, 42); // six weeks
    expect(c.month.take(6), everyElement(isNull));
    expect(c.month[6], DotState.missed); // Sun 1st, due but not done
    expect(c.month[6 + 2], DotState.done); // Tue 3rd
    expect(c.month[6 + 17], DotState.today); // Wed 18th
    expect(c.month[6 + 18], DotState.upcoming); // Thu 19th
    expect(c.month.sublist(6 + 30), everyElement(isNull)); // after the 30th
  });

  test('days a habit is not scheduled on show as off, not missed', () async {
    final id = await db.insertHabit(HabitsCompanion.insert(
      name: 'Gym',
      iconKey: 'gym',
      colorValue: 0xFFFF6B2C,
      scheduleType: Value(ScheduleType.weekdays.index),
      weekdayMask: const Value(0x01), // Mondays only
      createdAt: Value(DateTime(2026, 11, 1)),
    ));
    final c = await card(id);
    expect(c.month[7], DotState.missed); // Mon 2nd: due, not done
    expect(c.month[8], DotState.off); // Tue 3rd: not a scheduled day
  });

  test('the ring card shows what is done so far', () async {
    final id = await habit(target: 4);
    await db.setCompletion(habitId: id, day: '2026-11-18', amount: 1);
    final c = await card(id);
    expect(c.progress, 0.25);
    expect(c.done, isFalse);
    expect(c.countText, '1/4');
    expect(c.tappable, isTrue);
    expect(c.streakNoun, 'day');
  });

  test('cards for the same data have the same fingerprint, and differ when it changes', () async {
    final id = await habit();
    final a = await card(id);
    expect((await card(id)).fingerprint, a.fingerprint);
    await db.setCompletion(habitId: id, day: '2026-11-18', amount: 1);
    expect((await card(id)).fingerprint, isNot(a.fingerprint));
  });

  testWidgets('every card kind draws to a PNG', (tester) async {
    final id = await tester.runAsync(() => habit(target: 3)) as int;
    final c = (await tester.runAsync(() => card(id)))!;
    for (final kind in CardKind.values) {
      for (final white in [true, false]) {
        final bytes = (await tester.runAsync(() => renderCardPng(kind, [c, c], whiteInk: white)))!;
        expect(bytes.sublist(1, 4), [0x50, 0x4E, 0x47], reason: '$kind white=$white'); // "PNG"
      }
    }
  });

  testWidgets('syncing writes a picture per habit, kind and ink, and removes the ones left behind', (tester) async {
    final dir = Directory.systemTemp.createTempSync('ember_cards');
    addTearDown(() => dir.deleteSync(recursive: true));
    final id = await tester.runAsync(() => habit()) as int;
    await tester.runAsync(() => WidgetCards.instance.sync(db, today, folder: dir, notifyWidgets: false));
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, containsAll(['ember_streak_${id}_c.png', 'ember_ring_${id}_w.png', 'ember_month_${id}_c.png', 'ember_grid_w.png']));
    expect(names.length, 12); // 5 kinds x 2 inks + the grid in 2 inks

    File('${dir.path}/ember_week_999_c.png').writeAsBytesSync([1]);
    await tester.runAsync(() async {
      await db.setCompletion(habitId: id, day: '2026-11-18', amount: 1); // changes the picture, so it redraws
      await WidgetCards.instance.sync(db, today, folder: dir, notifyWidgets: false);
    });
    expect(File('${dir.path}/ember_week_999_c.png').existsSync(), isFalse);
  });
}
