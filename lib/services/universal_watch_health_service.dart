import 'package:health/health.dart';

class UniversalWatchHealthSnapshot {
  final double heartRate;
  final int steps;
  final double sleepHours;
  final double activityLevel;
  final DateTime timestamp;
  final String source;

  const UniversalWatchHealthSnapshot({
    required this.heartRate,
    required this.steps,
    required this.sleepHours,
    required this.activityLevel,
    required this.timestamp,
    required this.source,
  });
}

/// Cross-platform health bridge.
/// Reads phone health store data (Apple Health / Health Connect), which can include
/// synced watch metrics from Apple Watch, boAt, Fit Pro, and similar devices.
class UniversalWatchHealthService {
  final Health _health = Health();

  Future<bool> requestReadPermissions() async {
    try {
      await _health.configure();

      final types = <HealthDataType>[
        HealthDataType.HEART_RATE,
        HealthDataType.STEPS,
        HealthDataType.SLEEP_ASLEEP,
      ];
      final permissions = List.filled(types.length, HealthDataAccess.READ);

      return await _health.requestAuthorization(types, permissions: permissions);
    } catch (_) {
      return false;
    }
  }

  Future<UniversalWatchHealthSnapshot?> fetchLatest({Duration lookback = const Duration(hours: 24)}) async {
    try {
      final end = DateTime.now();
      final start = end.subtract(lookback);
      final points = await _health.getHealthDataFromTypes(
        types: const [
          HealthDataType.HEART_RATE,
          HealthDataType.STEPS,
          HealthDataType.SLEEP_ASLEEP,
        ],
        startTime: start,
        endTime: end,
      );

      if (points.isEmpty) return null;

      final clean = _health.removeDuplicates(points)..sort((a, b) => b.dateTo.compareTo(a.dateTo));

      double? latestHeartRate;
      int latestSteps = 0;
      double sleepHours = 0;
      DateTime latestTs = end;

      for (final p in clean) {
        final type = p.type;
        final val = _asDouble(p.value);

        if (latestTs.isAfter(p.dateTo)) {
          latestTs = p.dateTo;
        }

        if (type == HealthDataType.HEART_RATE && latestHeartRate == null && val != null) {
          latestHeartRate = val;
        }

        if (type == HealthDataType.STEPS && val != null) {
          latestSteps += val.toInt();
        }

        if (type == HealthDataType.SLEEP_ASLEEP) {
          sleepHours += p.dateTo.difference(p.dateFrom).inMinutes / 60.0;
        }
      }

      if (latestHeartRate == null && latestSteps <= 0 && sleepHours <= 0) {
        return null;
      }

      return UniversalWatchHealthSnapshot(
        heartRate: (latestHeartRate ?? 0).clamp(0, 220).toDouble(),
        steps: latestSteps,
        sleepHours: sleepHours.clamp(0, 16),
        activityLevel: _deriveActivityLevel(latestSteps),
        timestamp: DateTime.now(),
        source: 'phone_health_sync',
      );
    } catch (_) {
      return null;
    }
  }

  double _deriveActivityLevel(int steps) {
    if (steps <= 2000) return 1.5;
    if (steps <= 4000) return 3.0;
    if (steps <= 7000) return 5.0;
    if (steps <= 10000) return 7.0;
    return 9.0;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    final text = value.toString();
    return double.tryParse(text.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  }
}
