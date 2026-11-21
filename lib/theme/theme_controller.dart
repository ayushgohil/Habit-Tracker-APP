import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ember_theme.dart';

const _themeKey = 'theme_id';

/// Holds the id of the selected look and remembers it between launches.
class ThemeController extends StateNotifier<String> {
  ThemeController() : super(emberPalettes.first.id) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_themeKey);
      if (id != null && mounted && emberPalettes.any((p) => p.id == id)) {
        state = id;
      }
    } catch (_) {
      // No saved look (or no storage, as in tests): keep the default.
    }
  }

  Future<void> select(String id) async {
    if (!emberPalettes.any((p) => p.id == id)) return;
    state = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, id);
    } catch (_) {}
  }
}

final themeIdProvider = StateNotifierProvider<ThemeController, String>((ref) => ThemeController());

const _autoKey = 'theme_auto';
const _darkKey = 'theme_dark';
const _lightKey = 'theme_light';

/// "Match the phone": a dark look and a light look, switched by the system.
class AutoTheme {
  const AutoTheme({this.enabled = false, this.darkId = 'ember', this.lightId = 'paper'});
  final bool enabled;
  final String darkId;
  final String lightId;

  AutoTheme copyWith({bool? enabled, String? darkId, String? lightId}) =>
      AutoTheme(enabled: enabled ?? this.enabled, darkId: darkId ?? this.darkId, lightId: lightId ?? this.lightId);
}

class AutoThemeController extends StateNotifier<AutoTheme> {
  AutoThemeController() : super(const AutoTheme()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      String pick(String key, bool dark, String fallback) {
        final id = prefs.getString(key);
        return emberPalettes.any((p) => p.id == id && p.dark == dark) ? id! : fallback;
      }

      state = AutoTheme(
        enabled: prefs.getBool(_autoKey) ?? false,
        darkId: pick(_darkKey, true, 'ember'),
        lightId: pick(_lightKey, false, 'paper'),
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoKey, state.enabled);
      await prefs.setString(_darkKey, state.darkId);
      await prefs.setString(_lightKey, state.lightId);
    } catch (_) {}
  }

  /// Turns following the phone on or off. Turning it on keeps the look in use
  /// as the dark or light one, whichever it is.
  Future<void> setEnabled(bool enabled, {EmberPalette? current}) async {
    var next = state.copyWith(enabled: enabled);
    if (enabled && current != null) {
      next = current.dark ? next.copyWith(darkId: current.id) : next.copyWith(lightId: current.id);
    }
    state = next;
    await _save();
  }

  /// Chooses [palette] for the side (dark or light) it belongs to.
  Future<void> select(EmberPalette palette) async {
    state = palette.dark ? state.copyWith(darkId: palette.id) : state.copyWith(lightId: palette.id);
    await _save();
  }
}

final autoThemeProvider = StateNotifierProvider<AutoThemeController, AutoTheme>((ref) => AutoThemeController());

/// Whether the phone is in dark or light mode; the app keeps it up to date.
final systemBrightnessProvider = StateProvider<Brightness>((ref) => PlatformDispatcher.instance.platformBrightness);

/// The look in use: the chosen one, or the dark/light one that matches the phone.
final activePaletteProvider = Provider<EmberPalette>((ref) {
  final auto = ref.watch(autoThemeProvider);
  if (!auto.enabled) return paletteById(ref.watch(themeIdProvider));
  final dark = ref.watch(systemBrightnessProvider) == Brightness.dark;
  return paletteById(dark ? auto.darkId : auto.lightId);
});
