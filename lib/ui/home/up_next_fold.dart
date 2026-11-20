import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _foldKey = 'up_next_open';

/// Whether the person has opened or folded the "Up next" list. Null means they
/// never chose, so the app picks by how many habits there are. Remembered
/// between launches.
class UpNextFold extends StateNotifier<bool?> {
  UpNextFold() : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_foldKey);
      // A tap made while this was loading wins over the saved value.
      if (saved != null && mounted && state == null) state = saved;
    } catch (_) {}
  }

  Future<void> set(bool open) async {
    state = open;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_foldKey, open);
    } catch (_) {}
  }
}

final upNextFoldProvider = StateNotifierProvider<UpNextFold, bool?>((ref) => UpNextFold());
