import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/day.dart';
import '../core/health.dart';
import '../data/database.dart';
import '../data/providers.dart';
import 'health_service.dart';

/// Where health numbers come from. Health Connect in the app, a fake in tests.
abstract class HealthSource {
  /// Whether Ember may already read [metric].
  Future<bool> hasPermission(HealthMetric metric);

  /// Asks the person for access to [metric]. True if it was granted.
  Future<bool> requestPermission(HealthMetric metric);

  /// The value for [day]: steps, or seconds of workout or sleep. Null if it
  /// could not be read.
  Future<int?> amountForDay(HealthMetric metric, DateTime day);
}

final healthSourceProvider = Provider<HealthSource>((ref) => HealthConnectSource());

/// Copies health numbers into the habits that are linked to them.
class HealthSync {
  HealthSync(this._db, this._source);
  final AppDatabase _db;
  final HealthSource _source;
  bool _running = false;

  /// Reads the last [days] days (never before a habit started) and raises each
  /// day to what the health app recorded. Returns how many days changed.
  Future<int> syncNow({int days = 3, DateTime? now}) async {
    if (_running) return 0;
    _running = true;
    try {
      final today = startOfDay(now ?? DateTime.now());
      final habits = await _db.healthLinkedHabits();
      var changed = 0;
      for (final habit in habits) {
        final metric = HealthMetric.fromIndex(habit.healthMetric);
        if (metric == HealthMetric.none) continue;
        if (!await _source.hasPermission(metric)) continue;
        final first = startOfDay(habit.createdAt);
        for (var i = days - 1; i >= 0; i--) {
          final day = addDays(today, -i);
          if (day.isBefore(first)) continue;
          final value = await _source.amountForDay(metric, day);
          if (value == null) continue;
          final key = dayKey(day);
          if (shouldRaise(logged: await _db.loggedAmount(habit.id, key), fromHealth: value)) {
            await _db.setCompletion(habitId: habit.id, day: key, amount: value);
            changed++;
          }
        }
      }
      return changed;
    } catch (error) {
      debugPrint('Ember health sync: $error');
      return 0;
    } finally {
      _running = false;
    }
  }
}

final healthSyncProvider = Provider<HealthSync>(
  (ref) => HealthSync(ref.watch(databaseProvider), ref.watch(healthSourceProvider)),
);
