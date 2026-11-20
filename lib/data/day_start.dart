import 'package:shared_preferences/shared_preferences.dart';

import '../core/day.dart';

const _dayStartKey = 'day_start_minutes';

/// The latest the day may start: 6am.
const maxDayStartMinutes = 6 * 60;

/// Reads the saved day-start time into [dayStartOffsetMinutes]. Call it before
/// anything that decides what "today" is, including code that runs while the
/// app is closed (widget taps, notification buttons).
Future<void> loadDayStart() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    dayStartOffsetMinutes = (prefs.getInt(_dayStartKey) ?? 0).clamp(0, maxDayStartMinutes).toInt();
  } catch (_) {
    // No saved value, or no storage (as in tests): the day starts at midnight.
  }
}

Future<void> saveDayStart(int minutes) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dayStartKey, minutes);
  } catch (_) {}
}
