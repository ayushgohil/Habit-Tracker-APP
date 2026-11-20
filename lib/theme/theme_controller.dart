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
