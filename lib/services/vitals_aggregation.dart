import 'dart:math' as math;

import 'vitals_repository.dart';

/// Pure heart-rate aggregation shared by the Health Connect path
/// (wearable_sync_service.dart) and mirrored 1:1 by the native Wear OS path
/// (android/app/.../WearVitalsUploader.kt). No Firebase imports: unit-tested in
/// test/vitals_aggregation_test.dart.
///
/// Why: Firestore Spark allows 20k writes/day for the whole project. One doc per
/// watch sample (~1/min) is ~1,440 writes per patient per day. We store ONE doc
/// per 5-minute window instead (<= 288/day), plus out-of-range samples as
/// individual `immediate` docs so threshold alerts are not delayed by the window.
/// See docs/DATA_MODEL.md "Free-tier budget".

/// Heart-rate alert thresholds (same defaults / bounds as
/// functions/src/logic/vitals.js and firestore.rules validThresholds).
class HrThresholds {
  final double high;
  final double low;
  const HrThresholds({this.high = defaultHigh, this.low = defaultLow});

  static const double defaultHigh = 120;
  static const double defaultLow = 45;

  /// Values at or beyond these are escalated to `critical` by the server.
  static const double criticalHigh = 150;
  static const double criticalLow = 40;

  /// Reads `users/{uid}.vitalThresholds` with the server's validation: an
  /// out-of-bounds or inverted override falls back to the defaults.
  factory HrThresholds.fromUserDoc(Map<String, dynamic>? user) {
    final t = user?['vitalThresholds'];
    if (t is! Map) return const HrThresholds();
    double pick(String k, double d, double lo, double hi) {
      final v = t[k];
      if (v is num && v.isFinite && v >= lo && v <= hi) return v.toDouble();
      return d;
    }

    final high = pick('heartRateHigh', defaultHigh, 80, 220);
    final low = pick('heartRateLow', defaultLow, 25, 80);
    if (low >= high) return const HrThresholds();
    return HrThresholds(high: high, low: low);
  }
}

/// One closed or open 5-minute window of heart-rate samples.
class HrWindow {
  final DateTime start; // UTC, aligned to 5 minutes since epoch
  final double sum;
  final int count;
  final double min;
  final double max;

  const HrWindow({
    required this.start,
    required this.sum,
    required this.count,
    required this.min,
    required this.max,
  });

  DateTime get end => start.add(HeartRateAggregation.windowLength);
  double get avg => sum / count;

  /// Value stored in the `vitals` doc: the mean, rounded to whole bpm.
  int get roundedAvg => avg.round();

  int get startMillis => start.millisecondsSinceEpoch;

  HrWindow add(double bpm) => HrWindow(
        start: start,
        sum: sum + bpm,
        count: count + 1,
        min: math.min(min, bpm),
        max: math.max(max, bpm),
      );
}

/// Daily heart-rate summary fields of `vitals_daily/{uid}_{yyyy-MM-dd}`.
class DailyHrSummary {
  /// 10th percentile of the day's 5-minute window means (a crude resting-HR
  /// proxy; null when fewer than [HeartRateAggregation.minWindowsForResting]).
  final int? restingEstimate;
  final int avg;
  final int min;
  final int max;
  final int windows;

  const DailyHrSummary({
    required this.restingEstimate,
    required this.avg,
    required this.min,
    required this.max,
    required this.windows,
  });
}

class HeartRateAggregation {
  HeartRateAggregation._();

  static const Duration windowLength = Duration(minutes: 5);
  static const int windowMillis = 5 * 60 * 1000;

  /// A resting estimate needs at least one hour of windows in the day.
  static const int minWindowsForResting = 12;

  /// Plausible bpm (same as the watch and the Kotlin uploader).
  static bool isPlausible(double bpm) => bpm.isFinite && bpm >= 20 && bpm <= 250;

  static DateTime windowStartOf(DateTime t) {
    final ms = t.toUtc().millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(ms - ms % windowMillis, isUtc: true);
  }

  /// Groups samples into 5-minute windows (oldest first). Implausible values
  /// are ignored; nothing is interpolated.
  static List<HrWindow> aggregate(Iterable<VitalReading> samples) {
    final byStart = <int, HrWindow>{};
    for (final s in samples) {
      if (s.type != VitalType.heartRate || !isPlausible(s.value)) continue;
      final start = windowStartOf(s.measuredAt);
      final key = start.millisecondsSinceEpoch;
      final prev = byStart[key];
      byStart[key] = prev == null
          ? HrWindow(start: start, sum: s.value, count: 1, min: s.value, max: s.value)
          : prev.add(s.value);
    }
    final out = byStart.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// 'high' | 'low' | null.
  static String? outOfRange(double bpm, HrThresholds t) {
    if (bpm > t.high) return 'high';
    if (bpm < t.low) return 'low';
    return null;
  }

  static bool isCritical(double bpm) => bpm >= HrThresholds.criticalHigh || bpm <= HrThresholds.criticalLow;

  /// Out-of-range samples to write immediately as individual `immediate` docs.
  ///
  /// Rate limit (to protect the free-tier write budget during e.g. a long run
  /// above the threshold): at most one per direction per 5-minute window, plus
  /// the first CRITICAL sample of that direction/window if the first one was
  /// not critical. The server already applies a 30-minute alert cooldown per
  /// patient + type + direction, so extra samples could not raise more alerts.
  static List<VitalReading> selectImmediate(Iterable<VitalReading> samples, HrThresholds t) {
    final sorted = samples.where((s) => s.type == VitalType.heartRate && isPlausible(s.value)).toList()
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    // key "<direction>:<windowStart>" -> already sent a critical one?
    final sent = <String, bool>{};
    final out = <VitalReading>[];
    for (final s in sorted) {
      final dir = outOfRange(s.value, t);
      if (dir == null) continue;
      final key = '$dir:${windowStartOf(s.measuredAt).millisecondsSinceEpoch}';
      final crit = isCritical(s.value);
      final prev = sent[key];
      if (prev == null || (!prev && crit)) {
        sent[key] = crit || (prev ?? false);
        out.add(s);
      }
    }
    return out;
  }

  /// Nearest-rank percentile (p in 0..1) of [values]; null when empty.
  static double? percentile(List<double> values, double p) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  /// Daily summary from the 5-minute windows of ONE local day. Null when no
  /// window exists (never a fabricated value).
  static DailyHrSummary? summarizeDay(Iterable<HrWindow> windows) {
    final list = windows.where((w) => w.count > 0).toList();
    if (list.isEmpty) return null;
    final avgs = list.map((w) => w.avg).toList();
    final mean = avgs.reduce((a, b) => a + b) / avgs.length;
    return DailyHrSummary(
      restingEstimate: list.length >= minWindowsForResting ? percentile(avgs, 0.10)!.round() : null,
      avg: mean.round(),
      min: list.map((w) => w.min).reduce(math.min).round(),
      max: list.map((w) => w.max).reduce(math.max).round(),
      windows: list.length,
    );
  }

  /// Patient-local calendar date `yyyy-MM-dd` (the `vitals_daily` key).
  static String localDateKey(DateTime t) {
    final l = t.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  static String dailyDocId(String patientId, String dateKey) => '${patientId}_$dateKey';
}
