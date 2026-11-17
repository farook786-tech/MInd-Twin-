import 'dart:math' as math;

import 'clinical_scoring.dart' show AssessmentRecord, EarlyWarning;

/// Digital Twin drift index — an EARLY-WARNING, PERSONAL-BASELINE signal.
///
/// It compares the patient only with themself: for each signal a robust personal
/// baseline (median + MAD) is learnt from the last 28 days, and the latest few days
/// are scored by how far they moved in the clinically WORSE direction. It is NOT a
/// diagnosis or a risk prediction, and it never feeds the clinical level
/// (ClinicalScoring stays instrument-based); the therapist card may list it under
/// early warnings only. Pure Dart, unit-tested (test/digital_twin_service_test.dart).
///
/// Method (documented in docs/CLINICAL_SAFETY_CASE.md and docs/DATA_MODEL.md):
/// * Data: `vitals_daily` (hrRestingEstimate, sleepHours, steps), `daily_logs`
///   (check-in wellbeing 0-100; higher = better), `clinical_assessments` (PHQ-9, GAD-7).
///   One value per local day (mean when several). Missing days stay missing.
/// * Recent window: 3 days. Sleep and check-ins include today; resting HR and steps use
///   the 3 COMPLETE days ending yesterday (today's values are partial). PHQ-9 / GAD-7
///   use the latest result of the last 7 days (instruments are taken every 1-2 weeks).
/// * Baseline: every value in the 28-day span before the recent window.
///   Needs >= 7 days (daily signals) or >= 2 results (PHQ-9 / GAD-7), else the signal
///   shows "learning baseline: N/7 days". Recent value = median of the recent days and
///   needs >= 2 of 3 days (daily signals).
/// * Deviation: robust z = (recent - median) / scale, scale = max(1.4826 * MAD, floor).
///   The floor (e.g. 3 bpm, 0.5 h, PHQ-9 2.5 = half its 5-point minimal important
///   change) stops a very regular baseline (MAD ~ 0) from turning noise into alarms.
/// * Worse direction only: resting HR up, sleep down (or > 2 units ABOVE baseline:
///   hypersomnia), steps down, wellbeing down, PHQ-9 / GAD-7 up. Score = clamp(z, 0, 4).
/// * Index 0-100 = 100 * sum(w * score / 4) / sum(w) over signals that have a score
///   (missing signals neither add nor dilute). Weights: [weights].
/// * Level: index < 25 stable, < 50 watch, >= 50 drifting; at least `watch` when any
///   one signal scores >= 3; at most `watch` when fewer than 2 signals have a score.
///   No scored signal -> `learning`.
enum DriftSignal { restingHr, sleep, steps, checkIn, phq9, gad7 }

enum DriftLevel { learning, stable, watch, drifting }

extension DriftLevelX on DriftLevel {
  String get label => switch (this) {
        DriftLevel.learning => 'Learning baseline',
        DriftLevel.stable => 'Stable',
        DriftLevel.watch => 'Watch',
        DriftLevel.drifting => 'Drifting',
      };

  /// Patient-facing wording: never alarming, never more than stable / watch.
  String get patientLabel => switch (this) {
        DriftLevel.learning => 'Still learning your usual pattern',
        DriftLevel.stable => 'Close to your usual',
        DriftLevel.watch || DriftLevel.drifting => 'Some changes from your usual',
      };
}

/// One value for one local calendar day.
class DatedValue {
  final DateTime day; // local midnight
  final double value;
  DatedValue(DateTime t, this.value) : day = DateTime(t.year, t.month, t.day);
}

class SignalSpec {
  final DriftSignal signal;
  final String label;
  final String patientLabel;
  final String unit;
  final double weight;

  /// Minimum robust scale (same unit as the signal).
  final double scaleFloor;

  /// +1: higher is worse; -1: lower is worse.
  final int worse;
  final bool includeToday;
  final bool instrument;
  final int decimals;

  const SignalSpec({
    required this.signal,
    required this.label,
    required this.patientLabel,
    required this.unit,
    required this.weight,
    required this.scaleFloor,
    required this.worse,
    required this.includeToday,
    this.instrument = false,
    this.decimals = 0,
  });
}

class SignalDrift {
  final SignalSpec spec;

  /// Days (or results) in the baseline span with data, and how many are required.
  final int baselineCount;
  final int requiredBaseline;
  final double? baselineMedian;
  final double? scale;

  /// Median of the recent window (latest result for instruments).
  final double? recent;
  final int recentDays;

  /// Recent days individually >= 1 unit worse than baseline.
  final int recentDaysWorse;

  /// Signed robust z of [recent] (null when not computable).
  final double? robustZ;

  /// 0..4 in the worse direction; null when the signal is not scored.
  final double? score;

  /// 28 daily values, oldest first (null = no data that day).
  final List<double?> series;

  const SignalDrift({
    required this.spec,
    required this.baselineCount,
    required this.requiredBaseline,
    required this.baselineMedian,
    required this.scale,
    required this.recent,
    required this.recentDays,
    required this.recentDaysWorse,
    required this.robustZ,
    required this.score,
    required this.series,
  });

  bool get hasAnyData => series.any((v) => v != null) || baselineCount > 0 || recent != null;
  bool get scored => score != null;

  String _fmt(double v) {
    if (spec.signal == DriftSignal.steps) return _thousands(v.round());
    return v.toStringAsFixed(spec.decimals);
  }

  static String _thousands(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return n < 0 ? '-$b' : b.toString();
  }

  /// Therapist status line, e.g. "Resting HR 78 bpm vs your usual 64 bpm (+2.4 MAD), 3 of last 3 days".
  String get therapistText {
    if (!hasAnyData) return '${spec.label}: no data';
    if (baselineCount < requiredBaseline) {
      return '${spec.label}: learning baseline: $baselineCount/$requiredBaseline '
          '${spec.instrument ? 'results' : 'days'}';
    }
    if (recent == null) {
      return '${spec.label}: no recent data '
          '(${spec.instrument ? 'last 7 days' : 'needs 2 of the last 3 days'})';
    }
    final z = robustZ!;
    final sign = z >= 0 ? '+' : '−';
    final unit = spec.unit.isEmpty ? '' : ' ${spec.unit}';
    final days = spec.instrument ? '' : ', $recentDaysWorse of last $recentDays days';
    final much = (spec.signal == DriftSignal.sleep && z > 2) ? ' (much more than usual)' : '';
    return '${spec.label} ${_fmt(recent!)}$unit vs your usual ${_fmt(baselineMedian!)}$unit '
        '($sign${z.abs().toStringAsFixed(1)} MAD)$much$days';
  }

  /// Gentle patient line (no z, no index).
  String get patientText {
    if (!hasAnyData) return 'No data yet';
    if (baselineCount < requiredBaseline) {
      return 'Learning your usual: $baselineCount of $requiredBaseline '
          '${spec.instrument ? 'questionnaires' : 'days'}';
    }
    if (recent == null) return 'Nothing recent to compare';
    final s = score ?? 0;
    if (s < 1) return 'Close to your usual';
    if (spec.instrument) return 'A little higher than your usual lately';
    final unit = spec.unit.isEmpty ? '' : ' ${spec.unit}';
    final dir = (robustZ ?? 0) > 0 ? 'more' : 'less';
    final what = switch (spec.signal) {
      DriftSignal.restingHr => 'Resting heart rate a bit higher than usual',
      DriftSignal.sleep => 'Sleeping $dir than usual',
      DriftSignal.steps => 'Moving less than usual',
      DriftSignal.checkIn => 'Check-ins a bit lower than usual',
      _ => 'Different from usual',
    };
    return '$what (about ${_fmt(recent!)}$unit vs ${_fmt(baselineMedian!)}$unit)';
  }
}

class DriftResult {
  /// 0..100, null when no signal could be scored.
  final int? index;
  final DriftLevel level;
  final List<SignalDrift> signals;
  final DateTime asOf;

  const DriftResult({required this.index, required this.level, required this.signals, required this.asOf});

  List<SignalDrift> get contributing =>
      signals.where((s) => (s.score ?? 0) >= 1).toList()..sort((a, b) => b.score!.compareTo(a.score!));

  /// Therapist explanations: contributing signals first (largest first), then the rest.
  List<String> get explanations => [
        ...contributing.map((s) => s.therapistText),
        ...signals.where((s) => (s.score ?? 0) < 1).map((s) => s.therapistText),
      ];

  /// Entry for ClinicalStatusCard "Early-warning signals (not diagnostic)". Never
  /// changes the clinical level. Null while learning.
  EarlyWarning? toEarlyWarning() {
    if (index == null || level == DriftLevel.learning) return null;
    final top = contributing.take(2).map((s) => s.spec.label).join(', ');
    return EarlyWarning(
      source: 'Digital Twin drift (personal baseline)',
      detail: '$index/100 (${level.label.toLowerCase()})${top.isEmpty ? '' : ': $top'}',
      at: asOf,
      flagged: level == DriftLevel.drifting,
    );
  }
}

class DigitalTwinService {
  DigitalTwinService._();

  static const int spanDays = 28;
  static const int recentDays = 3;
  static const int instrumentRecentDays = 7;
  static const int minBaselineDays = 7;
  static const int minBaselineResults = 2;
  static const int minRecentDays = 2;
  static const double maxScore = 4;

  static const List<SignalSpec> specs = [
    SignalSpec(
      signal: DriftSignal.restingHr,
      label: 'Resting HR',
      patientLabel: 'Resting heart rate',
      unit: 'bpm',
      weight: 1.0,
      scaleFloor: 3,
      worse: 1,
      includeToday: false,
    ),
    SignalSpec(
      signal: DriftSignal.sleep,
      label: 'Sleep',
      patientLabel: 'Sleep',
      unit: 'h',
      weight: 1.0,
      scaleFloor: 0.5,
      worse: -1,
      includeToday: true,
      decimals: 1,
    ),
    SignalSpec(
      signal: DriftSignal.steps,
      label: 'Steps',
      patientLabel: 'Steps',
      unit: '/day',
      weight: 0.75,
      scaleFloor: 1000,
      worse: -1,
      includeToday: false,
    ),
    SignalSpec(
      signal: DriftSignal.checkIn,
      label: 'Check-in wellbeing',
      patientLabel: 'Daily check-in',
      unit: '/100',
      weight: 1.0,
      scaleFloor: 7,
      worse: -1,
      includeToday: true,
    ),
    SignalSpec(
      signal: DriftSignal.phq9,
      label: 'PHQ-9',
      patientLabel: 'Mood questionnaire',
      unit: '',
      weight: 1.5,
      scaleFloor: 2.5,
      worse: 1,
      includeToday: true,
      instrument: true,
    ),
    SignalSpec(
      signal: DriftSignal.gad7,
      label: 'GAD-7',
      patientLabel: 'Anxiety questionnaire',
      unit: '',
      weight: 1.0,
      scaleFloor: 2,
      worse: 1,
      includeToday: true,
      instrument: true,
    ),
  ];

  /// Weights by signal (documented; instruments are validated so PHQ-9 weighs more,
  /// steps vary with weekdays so weigh less).
  static Map<DriftSignal, double> get weights => {for (final s in specs) s.signal: s.weight};

  static double? median(List<double> xs) {
    if (xs.isEmpty) return null;
    final s = [...xs]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  static double? mad(List<double> xs) {
    final m = median(xs);
    if (m == null) return null;
    return median(xs.map((x) => (x - m).abs()).toList());
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Collapses to one value per day (mean), keyed by local midnight.
  static Map<DateTime, double> _perDay(List<DatedValue> values) {
    final sum = <DateTime, double>{};
    final n = <DateTime, int>{};
    for (final v in values) {
      if (!v.value.isFinite) continue;
      sum[v.day] = (sum[v.day] ?? 0) + v.value;
      n[v.day] = (n[v.day] ?? 0) + 1;
    }
    return {for (final d in sum.keys) d: sum[d]! / n[d]!};
  }

  /// Worse-direction score from a signed robust z.
  static double worseScore(SignalSpec spec, double z) {
    double s;
    if (spec.signal == DriftSignal.sleep) {
      // Less sleep is worse; much MORE sleep (> 2 units) is also flagged (hypersomnia).
      s = z < 0 ? -z : (z > 2 ? z : 0);
    } else {
      s = spec.worse > 0 ? z : -z;
    }
    return s.clamp(0, maxScore).toDouble();
  }

  static SignalDrift _signal(SignalSpec spec, List<DatedValue> raw, DateTime now) {
    final today = _day(now);
    final first = today.subtract(const Duration(days: spanDays - 1));
    final perDay = _perDay(raw)..removeWhere((d, _) => d.isBefore(first) || d.isAfter(today));
    final series = [
      for (var i = 0; i < spanDays; i++) perDay[DateTime(first.year, first.month, first.day + i)],
    ];

    final lastRecent = spec.includeToday ? today : today.subtract(const Duration(days: 1));
    final windowDays = spec.instrument ? instrumentRecentDays : recentDays;
    final recentStart = DateTime(lastRecent.year, lastRecent.month, lastRecent.day - (windowDays - 1));

    final baselineVals = <double>[];
    final recentEntries = <MapEntry<DateTime, double>>[];
    for (final e in perDay.entries) {
      if (e.key.isBefore(recentStart)) {
        baselineVals.add(e.value);
      } else if (!e.key.isAfter(lastRecent)) {
        recentEntries.add(e);
      }
    }
    recentEntries.sort((a, b) => a.key.compareTo(b.key));
    final required = spec.instrument ? minBaselineResults : minBaselineDays;

    double? recent;
    if (spec.instrument) {
      recent = recentEntries.isEmpty ? null : recentEntries.last.value;
    } else if (recentEntries.length >= minRecentDays) {
      recent = median(recentEntries.map((e) => e.value).toList());
    }

    final med = median(baselineVals);
    final m = mad(baselineVals);
    final scale = m == null ? null : math.max(1.4826 * m, spec.scaleFloor);

    double? z;
    double? score;
    var daysWorse = 0;
    if (baselineVals.length >= required && recent != null && med != null && scale != null) {
      z = (recent - med) / scale;
      score = worseScore(spec, z);
      for (final e in recentEntries) {
        if (worseScore(spec, (e.value - med) / scale) >= 1) daysWorse++;
      }
    }
    return SignalDrift(
      spec: spec,
      baselineCount: baselineVals.length,
      requiredBaseline: required,
      baselineMedian: med,
      scale: scale,
      recent: recent,
      recentDays: spec.instrument ? recentEntries.length : recentEntries.length,
      recentDaysWorse: daysWorse,
      robustZ: z,
      score: score,
      series: series,
    );
  }

  /// Computes the drift result. [data] may omit signals (they are listed as "no data").
  static DriftResult compute({required Map<DriftSignal, List<DatedValue>> data, required DateTime now}) {
    final signals = [for (final spec in specs) _signal(spec, data[spec.signal] ?? const [], now)];
    final scored = signals.where((s) => s.scored).toList();
    if (scored.isEmpty) {
      return DriftResult(index: null, level: DriftLevel.learning, signals: signals, asOf: now);
    }
    var wSum = 0.0;
    var acc = 0.0;
    for (final s in scored) {
      wSum += s.spec.weight;
      acc += s.spec.weight * (s.score! / maxScore);
    }
    final index = (100 * acc / wSum).round().clamp(0, 100);
    var level = index >= 50
        ? DriftLevel.drifting
        : index >= 25
            ? DriftLevel.watch
            : DriftLevel.stable;
    final strongest = scored.map((s) => s.score!).reduce(math.max);
    if (level == DriftLevel.stable && strongest >= 3) level = DriftLevel.watch;
    if (level == DriftLevel.drifting && scored.length < 2) level = DriftLevel.watch;
    return DriftResult(index: index, level: level, signals: signals, asOf: now);
  }

  // ------------------------------------------------------------------ input adapters

  /// From `vitals_daily` docs (`date` 'yyyy-MM-dd' = patient-local day).
  static void addVitalsDaily(Map<DriftSignal, List<DatedValue>> out, Iterable<Map<String, dynamic>> docs) {
    for (final d in docs) {
      final day = _parseDate(d['date']);
      if (day == null) continue;
      void put(DriftSignal s, Object? v) {
        if (v is num && v.isFinite) out.putIfAbsent(s, () => []).add(DatedValue(day, v.toDouble()));
      }

      put(DriftSignal.restingHr, d['hrRestingEstimate']);
      put(DriftSignal.sleep, d['sleepHours']);
      put(DriftSignal.steps, d['steps']);
    }
  }

  /// From `daily_logs`: wellbeingScore (0-100, higher = better); older logs without it
  /// but with the check-in riskScore use 100 - riskScore (the same definition the
  /// check-in screen uses to write wellbeingScore).
  static void addDailyLogs(
    Map<DriftSignal, List<DatedValue>> out,
    Iterable<({DateTime at, double? wellbeing, double? riskScore})> logs,
  ) {
    for (final l in logs) {
      final w = l.wellbeing ?? (l.riskScore == null ? null : 100 - l.riskScore!);
      if (w == null || !w.isFinite || w < 0 || w > 100) continue;
      out.putIfAbsent(DriftSignal.checkIn, () => []).add(DatedValue(l.at.toLocal(), w));
    }
  }

  /// From normalised `clinical_assessments`.
  static void addAssessments(Map<DriftSignal, List<DatedValue>> out, Iterable<AssessmentRecord> records) {
    for (final r in records) {
      final at = r.at;
      if (at == null) continue;
      if (r.phq9Total != null) {
        out.putIfAbsent(DriftSignal.phq9, () => []).add(DatedValue(at.toLocal(), r.phq9Total!.toDouble()));
      }
      if (r.gad7Total != null) {
        out.putIfAbsent(DriftSignal.gad7, () => []).add(DatedValue(at.toLocal(), r.gad7Total!.toDouble()));
      }
    }
  }

  static DateTime? _parseDate(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
}
