import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/providers.dart';
import 'card_data.dart';
import 'card_painter.dart';

/// Keeps the images behind Ember's card widgets up to date.
///
/// The home screen can only show a picture, so every habit's streak, ring,
/// week, trend and month cards are drawn here as PNGs (one set in the habit's
/// colour for the dark style, one in white for the colour and glass styles).
/// The Android widgets pick the one they were set up with.
class WidgetCards {
  WidgetCards._();
  static final instance = WidgetCards._();

  static const _qualifiedPrefix = 'com.nextlyr.ember.';

  /// Android widget classes, one per card kind.
  static const providers = {
    CardKind.streak: 'EmberStreakWidget',
    CardKind.ring: 'EmberRingWidget',
    CardKind.week: 'EmberWeekWidget',
    CardKind.trend: 'EmberTrendWidget',
    CardKind.month: 'EmberMonthWidget',
    CardKind.grid: 'EmberGridWidget',
  };

  String? _last;
  bool _running = false;
  bool _again = false;

  /// Redraws the cards for [day] if anything changed since the last time.
  /// Overlapping calls are folded into one more pass.
  Future<void> sync(AppDatabase db, DateTime day, {Directory? folder, bool notifyWidgets = true}) async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _pass(db, day, folder, notifyWidgets);
      } while (_again);
    } catch (error) {
      debugPrint('Ember widget cards: $error');
    } finally {
      _running = false;
    }
  }

  Future<void> _pass(AppDatabase db, DateTime day, Directory? folder, bool notifyWidgets) async {
    final views = await loadViewsOn(db, day);
    final histories = {for (final h in await loadHistoriesOn(db, day)) h.habit.id: h};
    final cards = [
      for (final v in views)
        if (histories[v.habit.id] != null) buildCardHabit(v, histories[v.habit.id]!, day),
    ];
    final fingerprint = cards.map((c) => c.fingerprint).join('\n');
    if (fingerprint == _last) return;

    final dir = folder ?? await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final wanted = <String>{};
    Future<void> write(String name, CardKind kind, List<CardHabit> habits, bool white) async {
      final file = '${dir.path}${Platform.pathSeparator}$name';
      await File(file).writeAsBytes(await renderCardPng(kind, habits, whiteInk: white), flush: true);
      wanted.add(name);
    }

    for (final white in [false, true]) {
      final ink = white ? 'w' : 'c';
      for (final card in cards) {
        for (final kind in [CardKind.streak, CardKind.ring, CardKind.week, CardKind.trend, CardKind.month]) {
          await write('ember_${kind.name}_${card.id}_$ink.png', kind, [card], white);
        }
      }
      // The grid shows what is still to do first.
      final grid = [...cards.where((c) => !c.done), ...cards.where((c) => c.done)];
      if (grid.isNotEmpty) await write('ember_grid_$ink.png', CardKind.grid, grid, white);
    }
    // Drop pictures of habits that no longer exist.
    for (final entity in dir.listSync()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File && name.startsWith('ember_') && name.endsWith('.png') && !wanted.contains(name)) {
        entity.deleteSync();
      }
    }
    _last = fingerprint;
    if (!notifyWidgets) return;

    try {
      await HomeWidget.saveWidgetData<String>('ember_img_dir', dir.path);
      // One line per habit: id, name, colour, whether a tap on the widget logs it.
      await HomeWidget.saveWidgetData<String>(
        'ember_habits',
        [for (final c in cards) '${c.id}\t${c.name.replaceAll(RegExp(r'[\t\n]'), ' ')}\t${c.colorValue}\t${c.tappable ? 1 : 0}']
            .join('\n'),
      );
      for (final name in providers.values) {
        await HomeWidget.updateWidget(androidName: name, qualifiedAndroidName: '$_qualifiedPrefix$name');
      }
    } catch (error) {
      // No widget plugin (tests) or no widget placed: never a reason to fail.
      debugPrint('Ember widget cards: $error');
    }
  }
}
