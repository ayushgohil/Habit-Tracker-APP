import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../core/day.dart';
import '../core/health.dart';
import 'health_sync.dart';

/// Reads steps, workouts and sleep from Health Connect.
class HealthConnectSource implements HealthSource {
  final Health _health = Health();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  List<HealthDataType> _types(HealthMetric metric) => switch (metric) {
        HealthMetric.steps => [HealthDataType.STEPS],
        HealthMetric.exercise => [HealthDataType.WORKOUT],
        HealthMetric.sleep => [HealthDataType.SLEEP_SESSION],
        HealthMetric.none => const [],
      };

  @override
  Future<bool> hasPermission(HealthMetric metric) async {
    final types = _types(metric);
    if (types.isEmpty) return false;
    try {
      await _ensureConfigured();
      return await _health.hasPermissions(types, permissions: [HealthDataAccess.READ]) ?? false;
    } catch (error) {
      debugPrint('Ember health: $error');
      return false;
    }
  }

  @override
  Future<bool> requestPermission(HealthMetric metric) async {
    final types = _types(metric);
    if (types.isEmpty) return false;
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(types, permissions: [HealthDataAccess.READ]);
    } catch (error) {
      debugPrint('Ember health: $error');
      return false;
    }
  }

  @override
  Future<int?> amountForDay(HealthMetric metric, DateTime day) async {
    try {
      await _ensureConfigured();
      final start = startOfDay(day);
      final end = addDays(start, 1);
      if (metric == HealthMetric.steps) {
        return await _health.getTotalStepsInInterval(start, end);
      }
      final window = fetchWindowFor(day);
      final points = await _health.getHealthDataFromTypes(
        types: _types(metric),
        startTime: window.from,
        endTime: window.to,
      );
      final samples = [for (final p in points) HealthSample(p.dateFrom, p.dateTo)];
      return metric == HealthMetric.sleep
          ? sleepSecondsForDay(samples, day)
          : exerciseSecondsOnDay(samples, day);
    } catch (error) {
      debugPrint('Ember health: $error');
      return null;
    }
  }
}
