import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/core/day.dart';
import 'package:ember/core/link.dart';
import 'package:ember/data/backup.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:ember/health/health_writer.dart';
import 'package:ember/security/app_lock.dart';
import 'package:ember/ui/common/open_link.dart';
import 'package:ember/widgets/widget_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'add_habit_helpers.dart';
import 'home_flow_test.dart' show settle;

class FakeAuth implements LockAuthenticator {
  bool available = true;
  bool passes = true;
  final reasons = <String>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    return passes;
  }
}

class FakeWriter implements HealthWriter {
  final writes = <int>[];

  @override
  Future<bool> requestWaterPermission() async => true;

  @override
  Future<void> writeWater(int millilitres, DateTime time) async => writes.add(millilitres);
}

class FakeOpener implements LinkOpener {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

void main() {
  group('links', () {
    test('web addresses get https and app links are kept', () {
      expect(normalizeLink(''), '');
      expect(normalizeLink('   '), '');
      expect(normalizeLink('example.com'), 'https://example.com');
      expect(normalizeLink(' https://example.com/a?b=1 '), 'https://example.com/a?b=1');
      expect(normalizeLink('http://example.com'), 'http://example.com');
      expect(normalizeLink('whatsapp://send?phone=1'), 'whatsapp://send?phone=1');
      expect(normalizeLink('tel:+911234567890'), 'tel:+911234567890');
      expect(normalizeLink('example.com:8080/path'), 'https://example.com:8080/path');
    });

    test('anything that could read files or run script is refused', () {
      expect(normalizeLink('file:///sdcard/a'), isNull);
      expect(normalizeLink('javascript:alert(1)'), isNull);
      expect(normalizeLink('content://x/y'), isNull);
      expect(normalizeLink('data:text/html,hi'), isNull);
      expect(normalizeLink('two words'), isNull);
      expect(normalizeLink('nodots'), isNull);
    });
  });

  group('writing water to Health Connect', () {
    late AppDatabase db;
    late FakeWriter writer;
    late HealthWriter original;
    final today = startOfDay(DateTime.now());

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      writer = FakeWriter();
      original = healthWriter;
      healthWriter = writer;
    });
    tearDown(() async {
      healthWriter = original;
      await db.close();
    });

    Future<int> water({bool write = true, String unit = 'ml'}) => db.insertHabit(HabitsCompanion.insert(
          name: 'Water',
          iconKey: 'water',
          colorValue: 0xFF3DA5FF,
          dailyTarget: const Value(2000),
          unitLabel: Value(unit),
          stepSize: const Value(250),
          writeToHealth: Value(write),
          createdAt: Value(addDays(today, -2)),
        ));

    Future<HabitView> view(int id, [DateTime? day]) async =>
        (await loadViewsOn(db, day ?? today)).firstWhere((v) => v.habit.id == id);

    test('each drink added today is written once, as the amount that was added', () async {
      final id = await water();
      final actions = HabitActions(db);
      await actions.setAmount(await view(id), today, 250);
      expect(writer.writes, [250]);
      expect(await logTapFromWidget(db, id, today), isTrue); // a tap from a widget adds another step
      expect(writer.writes, [250, 250]);
    });

    test('lowering an amount, or logging a past day, writes nothing', () async {
      final id = await water();
      final actions = HabitActions(db);
      await actions.setAmount(await view(id), today, 500);
      writer.writes.clear();
      await actions.setAmount(await view(id), today, 100);
      await actions.setAmount(await view(id, addDays(today, -1)), addDays(today, -1), 750);
      expect(writer.writes, isEmpty);
    });

    test('nothing is written unless the habit asks for it and counts in ml', () async {
      final off = await water(write: false);
      final pages = await db.insertHabit(HabitsCompanion.insert(
        name: 'Pages',
        iconKey: 'book',
        colorValue: 0xFF5E9BFF,
        unitLabel: const Value('pages'),
        writeToHealth: const Value(true),
        createdAt: Value(addDays(today, -2)),
      ));
      final actions = HabitActions(db);
      await actions.setAmount(await view(off), today, 250);
      await actions.setAmount(await view(pages), today, 5);
      expect(writer.writes, isEmpty);
      expect(countsInMillilitres('ML'), isTrue);
      expect(countsInMillilitres('pages'), isFalse);
    });

    test('automation can complete a habit in one go, once', () async {
      final id = await db.insertHabit(HabitsCompanion.insert(
        name: 'Stretch',
        iconKey: 'stretch',
        colorValue: 0xFF7BD389,
        dailyTarget: const Value(3),
        createdAt: Value(addDays(today, -2)),
      ));
      expect(await completeFromAutomation(db, id, today), isTrue);
      expect((await view(id)).countToday, 3);
      expect((await view(id)).isDone, isTrue);
      expect(await completeFromAutomation(db, id, today), isFalse); // already done
      expect(await completeFromAutomation(db, 9999, today), isFalse); // no such habit
    });

    test('link and health settings survive a backup, and old backups restore them as off', () async {
      await water();
      await db.update(db.habits).write(const HabitsCompanion(linkUrl: Value('https://example.com')));
      final data = jsonDecode(await exportBackupJson(db)) as Map<String, dynamic>;
      await restoreBackupJson(db, jsonEncode(data));
      var habit = (await db.select(db.habits).get()).single;
      expect(habit.linkUrl, 'https://example.com');
      expect(habit.writeToHealth, isTrue);

      for (final h in data['habits'] as List) {
        (h as Map<String, dynamic>)
          ..remove('linkUrl')
          ..remove('writeToHealth');
      }
      await restoreBackupJson(db, jsonEncode(data));
      habit = (await db.select(db.habits).get()).single;
      expect(habit.linkUrl, '');
      expect(habit.writeToHealth, isFalse);
    });
  });

  group('in the app', () {
    late FakeAuth auth;
    late LinkOpener originalOpener;

    setUp(() {
      auth = FakeAuth();
      originalOpener = linkOpener;
    });
    tearDown(() => linkOpener = originalOpener);

    Future<AppDatabase> start(WidgetTester tester, {bool locked = false, Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 3000);
      addTearDown(tester.view.reset);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appLockInitialProvider.overrideWithValue(locked),
          lockAuthenticatorProvider.overrideWithValue(auth),
        ],
        child: const EmberApp(),
      ));
      await settle(tester);
      return db;
    }

    Future<void> stop(WidgetTester tester, AppDatabase db) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await tester.runAsync(db.close);
    }

    testWidgets('a locked app stays covered until the phone check passes', (tester) async {
      auth.passes = false;
      final db = await start(tester, locked: true);
      expect(find.byKey(const Key('lock-screen')), findsOneWidget);
      expect(auth.reasons, ['Unlock Ember']); // asked as soon as it opened

      await tester.tap(find.byKey(const Key('unlock-button')));
      await settle(tester);
      expect(find.byKey(const Key('lock-screen')), findsOneWidget); // failed again

      auth.passes = true;
      await tester.tap(find.byKey(const Key('unlock-button')));
      await settle(tester);
      expect(find.byKey(const Key('lock-screen')), findsNothing);
      await stop(tester, db);
    });

    testWidgets('with the lock off nothing covers the app', (tester) async {
      final db = await start(tester);
      expect(find.byKey(const Key('lock-screen')), findsNothing);
      expect(auth.reasons, isEmpty);
      await stop(tester, db);
    });

    Future<void> openPrivacy(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('privacy-open')));
      await tester.tap(find.byKey(const Key('privacy-open')));
      await settle(tester);
    }

    testWidgets('the lock is turned on from Privacy & automation after the phone confirms', (tester) async {
      final db = await start(tester);
      await openPrivacy(tester);
      await tester.tap(find.byKey(const Key('app-lock-switch')));
      await settle(tester);
      expect(auth.reasons, ['Turn on the Ember lock']);
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      expect(prefs.getBool('app_lock'), isTrue);
      expect(find.byKey(const Key('lock-screen')), findsNothing); // not locked out of the screen it was turned on in
      await stop(tester, db);
    });

    testWidgets('a phone with no screen lock cannot turn it on', (tester) async {
      auth.available = false;
      final db = await start(tester);
      await openPrivacy(tester);
      await tester.tap(find.byKey(const Key('app-lock-switch')));
      await settle(tester);
      expect(find.textContaining('Set up a screen lock'), findsOneWidget);
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      expect(prefs.getBool('app_lock'), isNull);
      await stop(tester, db);
    });

    testWidgets('the automation actions are listed with the package name', (tester) async {
      final db = await start(tester);
      await openPrivacy(tester);
      // The automation list is tucked away until it is opened.
      expect(find.byKey(const Key('action-LOG')), findsNothing);
      await tester.tap(find.byKey(const Key('automation-section')));
      await settle(tester);
      for (final name in ['LOG', 'COMPLETE', 'START', 'STOP']) {
        expect(find.byKey(Key('action-$name')), findsOneWidget, reason: name);
      }
      expect(find.text('com.nextlyr.ember.action.COMPLETE'), findsOneWidget);
      await stop(tester, db);
    });

    testWidgets('a habit link is saved cleaned up and opened from the details sheet', (tester) async {
      final fake = FakeOpener();
      linkOpener = fake;
      final db = await start(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Pray');
      await openStep(tester, 3);
      await tester.enterText(find.byKey(const Key('link-field')), 'example.com/start');
      await createHabit(tester);

      final saved = (await tester.runAsync(() => db.select(db.habits).get()))!.single;
      expect(saved.linkUrl, 'https://example.com/start');

      await tester.longPress(find.text('Pray').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('open-link')));
      await settle(tester);
      expect(fake.opened, ['https://example.com/start']);
      await stop(tester, db);
    });

    testWidgets('a link that cannot be opened stops the habit from being saved', (tester) async {
      final db = await start(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Pray');
      await openStep(tester, 3);
      await tester.enterText(find.byKey(const Key('link-field')), 'javascript:alert(1)');
      await tester.tap(find.byKey(const Key('primary-action')));
      await settle(tester);
      expect(find.textContaining('does not look right'), findsOneWidget);
      expect((await tester.runAsync(() => db.select(db.habits).get()))!, isEmpty);
      await stop(tester, db);
    });
  });
}
