import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:ember/app.dart';
import 'package:ember/data/database.dart';
import 'package:ember/data/providers.dart';
import 'package:ember/theme/ember_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_flow_test.dart' show settle;

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('there are at least 30 looks, in both dark and light, with unique ids', () {
    expect(emberPalettes.length, greaterThanOrEqualTo(30));
    expect(emberPalettes.map((p) => p.id).toSet().length, emberPalettes.length);
    expect(emberPalettes.where((p) => p.dark).length, greaterThan(15));
    expect(emberPalettes.where((p) => !p.dark).length, greaterThanOrEqualTo(8));
  });

  test('the new looks are readable', () {
    // The first twelve are the original hand-made looks.
    for (final p in emberPalettes.skip(12)) {
      expect(contrast(p.text, p.background), greaterThan(7), reason: '${p.id} text');
      expect(contrast(p.textMuted, p.background), greaterThan(4), reason: '${p.id} muted text');
      expect(contrast(p.accent, p.background), greaterThan(3.5), reason: '${p.id} accent');
      expect(contrast(p.glow, p.background), greaterThan(3.5), reason: '${p.id} glow');
      expect(contrast(p.onAccent, p.accent), greaterThan(4), reason: '${p.id} text on accent');
      expect(p.surface == p.background, isFalse, reason: '${p.id} surface');
      expect(() => emberTheme(p), returnsNormally);
    }
  });

  Future<AppDatabase> start(WidgetTester tester, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 800);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(() => EmberColors.use(emberPalettes.first));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
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

  testWidgets('with "match my phone" the look follows the phone between dark and light', (tester) async {
    final db = await start(tester, {'theme_auto': true, 'theme_dark': 'ocean', 'theme_light': 'sky'});
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await settle(tester);
    expect(EmberColors.palette.id, 'ocean');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await settle(tester);
    expect(EmberColors.palette.id, 'sky');
    await stop(tester, db);
  });

  testWidgets('without it the chosen look stays whatever the phone does', (tester) async {
    final db = await start(tester, {'theme_id': 'forest'});
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await settle(tester);
    expect(EmberColors.palette.id, 'forest');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await settle(tester);
    expect(EmberColors.palette.id, 'forest');
    await stop(tester, db);
  });

  testWidgets('turning it on keeps the current look and a light pick is saved for daytime', (tester) async {
    final db = await start(tester, {'theme_id': 'ocean'});
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.tap(find.byKey(const Key('appearance-button')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('auto-theme-switch')));
    await tester.tap(find.byKey(const Key('auto-theme-switch')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('theme-blush')));
    await tester.tap(find.byKey(const Key('theme-blush')));
    await settle(tester);
    expect(EmberColors.palette.id, 'blush'); // the phone is in light mode
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getBool('theme_auto'), isTrue);
    expect(prefs.getString('theme_dark'), 'ocean'); // the look that was in use became the dark one
    expect(prefs.getString('theme_light'), 'blush');
    await stop(tester, db);
  });
}
