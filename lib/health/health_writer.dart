import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../core/day.dart';
import '../data/database.dart';

/// Whether a habit counts in millilitres, so each log can be mirrored to
/// Health Connect as water.
bool countsInMillilitres(String unitLabel) {
  final unit = unitLabel.trim().toLowerCase();
  return unit == 'ml' || unit == 'millilitres' || unit == 'milliliters';
}

/// Writes what is logged to Health Connect.
abstract class HealthWriter {
  /// Asks for permission to add water. True if granted.
  Future<bool> requestWaterPermission();

  /// Adds [millilitres] of water ending at [time].
  Future<void> writeWater(int millilitres, DateTime time);
}

class HealthConnectWriter implements HealthWriter {
  final Health _health = Health();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> requestWaterPermission() async {
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization([HealthDataType.WATER], permissions: [HealthDataAccess.WRITE]);
    } catch (error) {
      debugPrint('Ember health write: $error');
      return false;
    }
  }

  @override
  Future<void> writeWater(int millilitres, DateTime time) async {
    try {
      await _ensureConfigured();
      await _health.writeHealthData(
        value: millilitres / 1000.0,
        unit: HealthDataUnit.LITER,
        type: HealthDataType.WATER,
        startTime: time.subtract(const Duration(minutes: 1)),
        endTime: time,
      );
    } catch (error) {
      debugPrint('Ember health write: $error');
    }
  }
}

/// The writer in use. Tests replace it.
HealthWriter healthWriter = HealthConnectWriter();

/// Call after a habit's amount for [day] changed from [before] to [after]:
/// water that was added today is written to Health Connect when the habit asks for it.
Future<void> mirrorToHealth(Habit habit, int before, int after, DateTime day) async {
  if (!habit.writeToHealth || !countsInMillilitres(habit.unitLabel)) return;
  if (after <= before || startOfDay(day) != startOfDay(currentDay())) return;
  await healthWriter.writeWater(after - before, DateTime.now());
}
