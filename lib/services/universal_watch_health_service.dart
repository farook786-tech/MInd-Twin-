import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'vitals_repository.dart';

/// Reads REAL measurements from the phone health store (Health Connect on Android,
/// HealthKit on iOS), which includes data synced from watches (Samsung Health, Fitbit, ...).
///
/// Every value returned carries its real measurement time. Nothing is padded, defaulted or
/// re-stamped: if there is no data, the lists are empty.
class UniversalWatchHealthService {
  final Health _health = Health();
  bool _configured = false;

  static const String _source = 'health_connect';

  static List<HealthDataType> get _sleepStageTypes => Platform.isAndroid
      ? const [
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
        ]
      : const [HealthDataType.SLEEP_ASLEEP];

  /// All types we read (each maps to one Health Connect READ permission:
  /// READ_HEART_RATE, READ_STEPS, READ_SLEEP).
  static List<HealthDataType> get readTypes => [
        HealthDataType.HEART_RATE,
        HealthDataType.STEPS,
        if (Platform.isAndroid) HealthDataType.SLEEP_SESSION,
        ..._sleepStageTypes,
      ];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// False when Health Connect is not installed / needs an update.
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      await _ensureConfigured();
      return await _health.isHealthConnectAvailable();
    } catch (e) {
      debugPrint('[Health] availability check failed: $e');
      return false;
    }
  }

  /// Android: true/false. iOS: HealthKit never reveals read access, so null → treated as ok.
  Future<bool> hasReadPermissions() async {
    try {
      await _ensureConfigured();
      final types = readTypes;
      final granted = await _health.hasPermissions(
        types,
        permissions: List.filled(types.length, HealthDataAccess.READ),
      );
      return granted ?? true;
    } catch (e) {
      debugPrint('[Health] hasPermissions failed: $e');
      return false;
    }
  }

  /// Shows the Health Connect permission sheet (requires FlutterFragmentActivity).
  Future<bool> requestReadPermissions() async {
    try {
      await _ensureConfigured();
      final types = readTypes;
      return await _health.requestAuthorization(
        types,
        permissions: List.filled(types.length, HealthDataAccess.READ),
      );
    } catch (e) {
      debugPrint('[Health] requestAuthorization failed: $e');
      return false;
    }
  }

  static double? _numeric(HealthDataPoint p) {
    final v = p.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  /// Individual heart-rate samples with dateTo in (from, to].
  Future<List<VitalReading>> readHeartRate(DateTime from, DateTime to) async {
    await _ensureConfigured();
    final points = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.HEART_RATE],
      startTime: from,
      endTime: to,
    );
    final out = <VitalReading>[];
    final seen = <int>{};
    for (final p in points) {
      final bpm = _numeric(p);
      if (bpm == null || bpm < 20 || bpm > 250) continue;
      if (!p.dateTo.isAfter(from) || p.dateTo.isAfter(to)) continue;
      final ms = p.dateTo.toUtc().millisecondsSinceEpoch;
      if (!seen.add(ms)) continue; // same instant from two origins → one doc id anyway
      out.add(VitalReading(
        type: VitalType.heartRate,
        value: bpm,
        measuredAt: p.dateTo.toUtc(),
        source: _source,
      ));
    }
    out.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return out;
  }

  /// One reading per night: total hours asleep for all sleep sessions that END in that
  /// night's window (local 18:00 previous day → 18:00), measuredAt = latest session end.
  /// Returns nights whose sessions end within [from, to].
  Future<List<VitalReading>> readSleepNights(DateTime from, DateTime to) async {
    await _ensureConfigured();
    final queryFrom = from.subtract(const Duration(hours: 24));

    final stages = await _health.getHealthDataFromTypes(
      types: _sleepStageTypes,
      startTime: queryFrom,
      endTime: to,
    );

    // Sessions: Android has explicit sessions. iOS: treat each asleep sample as a session.
    final sessions = Platform.isAndroid
        ? await _health.getHealthDataFromTypes(
            types: const [HealthDataType.SLEEP_SESSION],
            startTime: queryFrom,
            endTime: to,
          )
        : stages;

    final byNight = <DateTime, ({double minutes, DateTime end})>{};
    for (final s in sessions) {
      final start = s.dateFrom;
      final end = s.dateTo;
      if (!end.isAfter(start) || end.isBefore(from) || end.isAfter(to)) continue;

      double minutes;
      if (Platform.isAndroid) {
        // Sum asleep stages inside this session; fall back to session length if the
        // source app recorded no stages.
        minutes = 0;
        for (final st in stages) {
          final a = st.dateFrom.isAfter(start) ? st.dateFrom : start;
          final b = st.dateTo.isBefore(end) ? st.dateTo : end;
          if (b.isAfter(a)) minutes += b.difference(a).inSeconds / 60.0;
        }
        if (minutes <= 0) minutes = end.difference(start).inSeconds / 60.0;
      } else {
        minutes = end.difference(start).inSeconds / 60.0;
      }

      final local = end.toLocal();
      var night = DateTime(local.year, local.month, local.day);
      if (local.hour >= 18) night = night.add(const Duration(days: 1));
      final prev = byNight[night];
      byNight[night] = (
        minutes: (prev?.minutes ?? 0) + minutes,
        end: prev == null || end.isAfter(prev.end) ? end : prev.end,
      );
    }

    final out = <VitalReading>[];
    byNight.forEach((night, agg) {
      final hours = agg.minutes / 60.0;
      if (hours <= 0 || hours > 24) return;
      out.add(VitalReading(
        type: VitalType.sleep,
        value: double.parse(hours.toStringAsFixed(2)),
        measuredAt: agg.end.toUtc(),
        source: _source,
      ));
    });
    out.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return out;
  }

  /// One reading per local calendar day in [from, to] that has step data: the day's total
  /// (deduplicated across sources by the health store), measuredAt = end of the latest step
  /// record of that day.
  Future<List<VitalReading>> readDailySteps(DateTime from, DateTime to) async {
    await _ensureConfigured();
    final out = <VitalReading>[];
    final fromLocal = from.toLocal();
    var day = DateTime(fromLocal.year, fromLocal.month, fromLocal.day);
    while (!day.isAfter(to)) {
      final next = DateTime(day.year, day.month, day.day + 1);
      final end = next.isAfter(to) ? to : next;
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: day,
        endTime: end,
      );
      DateTime? latest;
      for (final p in points) {
        final t = p.dateTo.isAfter(end) ? end : p.dateTo;
        if (latest == null || t.isAfter(latest)) latest = t;
      }
      if (latest != null) {
        final total = await _health.getTotalStepsInInterval(day, end);
        if (total != null && total > 0) {
          out.add(VitalReading(
            type: VitalType.steps,
            value: total.toDouble(),
            measuredAt: latest.toUtc(),
            source: _source,
          ));
        }
      }
      day = next;
    }
    return out;
  }
}
