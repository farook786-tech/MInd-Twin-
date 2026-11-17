import 'dart:math';

import '../models/daily_log.dart';
import 'daily_log_source.dart';

// DECISION SUPPORT ONLY. Risk scores here are heuristic, not validated
// clinical instruments; they prioritise a therapist's attention and never
// replace clinical judgement. Evaluation: docs/ML_SAFETY_EVALUATION.md.
//
// Units / directions (DailyLog after DailyLogSource normalisation):
//   moodScore    0..10, 10 = best   -> risk 1 - mood/10
//   energyLevel  0..10, 10 = best   -> risk 1 - energy/10
//   sleepHours   0..24 hours        -> U-shaped: 0 inside 7..9 h, rising
//                                      linearly to 1 at 0 h and at >= 14 h
//   anxietyLevel 0..10, 10 = worst  -> risk anxiety/10 (ONLY when actually
//                                      recorded; the check-in does not collect
//                                      it and DailyLogSource defaults it to 5)
// Missing / NaN components are dropped and the remaining weights are
// renormalised; nothing is fabricated. Every component is monotonic: a worse
// input can never lower the score (enforced by test/ml_risk_scoring_test.dart).

class RiskPrediction {
  final double riskScore;
  final String riskLevel;
  final String trend;
  final List<double> prediction7Days;
  final List<String> keyFactors;
  final double confidence;
  final String source;

  const RiskPrediction({
    required this.riskScore,
    required this.riskLevel,
    required this.trend,
    required this.prediction7Days,
    required this.keyFactors,
    required this.confidence,
    required this.source,
  });
}

class MlRiskService {
  final DailyLogSource _dailyLogSource = DailyLogSource();

  static const double moodWeight = 0.40;
  static const double sleepWeight = 0.25;
  static const double energyWeight = 0.20;
  static const double anxietyWeight = 0.15;

  /// Days without a check-in after which the score is flagged as stale.
  static const int staleAfterDays = 3;

  /// Returns null when there is no check-in history (or it cannot be read):
  /// callers must show "no data" instead of a fabricated score (the old code
  /// returned a made-up 35 "moderate" / 40 on error).
  Future<RiskPrediction?> predictRisk(String patientId) async {
    final logs = await _dailyLogSource.getDailyLogs(patientId);
    return computeRisk(logs, now: DateTime.now());
  }

  static bool _ok(double? v) => v != null && v.isFinite;

  /// Sleep risk: 0 inside the healthy 7-9 h band, linear to 1 at 0 h and at 14 h.
  static double? sleepRisk(double? hours) {
    if (!_ok(hours) || hours! < 0) return null;
    if (hours < 7) return ((7 - hours) / 7).clamp(0.0, 1.0);
    if (hours > 9) return ((hours - 9) / 5).clamp(0.0, 1.0);
    return 0.0;
  }

  /// Per-day risk 0..100 from individual components (any may be null).
  /// Returns null when no component is usable.
  static double? componentRisk({
    double? mood0to10,
    double? sleepHours,
    double? energy0to10,
    double? anxiety0to10,
  }) {
    var weighted = 0.0;
    var weights = 0.0;
    void add(double? risk, double w) {
      if (risk == null || !risk.isFinite) return;
      weighted += risk.clamp(0.0, 1.0) * w;
      weights += w;
    }

    add(_ok(mood0to10) ? 1 - mood0to10!.clamp(0.0, 10.0) / 10 : null, moodWeight);
    add(sleepRisk(sleepHours), sleepWeight);
    add(_ok(energy0to10) ? 1 - energy0to10!.clamp(0.0, 10.0) / 10 : null, energyWeight);
    add(_ok(anxiety0to10) ? anxiety0to10!.clamp(0.0, 10.0) / 10 : null, anxietyWeight);
    if (weights == 0) return null;
    return (weighted / weights * 100).clamp(0.0, 100.0);
  }

  /// Per-log risk. Anxiety is ignored unless [anxietyRecorded] is true
  /// (DailyLog fields are null when not recorded).
  static double? logRisk(DailyLog log, {bool anxietyRecorded = false}) => componentRisk(
        mood0to10: log.moodScore,
        sleepHours: log.sleepHours,
        energy0to10: log.energyLevel,
        anxiety0to10: anxietyRecorded ? log.anxietyLevel : null,
      );

  static String riskLevelFor(double score) {
    if (score >= 75) return 'critical';
    if (score >= 50) return 'high';
    if (score >= 25) return 'moderate';
    return 'low';
  }

  /// Pure scoring over newest-first or unordered [logs]; null when no usable log.
  static RiskPrediction? computeRisk(List<DailyLog> logs, {required DateTime now, bool anxietyRecorded = false}) {
    final sorted = logs.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final scored = <MapEntry<DailyLog, double>>[];
    for (final log in sorted) {
      final r = logRisk(log, anxietyRecorded: anxietyRecorded);
      if (r != null) scored.add(MapEntry(log, r));
    }
    if (scored.isEmpty) return null;

    final recent = scored.take(7).toList();
    final latest = recent.first.value;
    final mean = recent.map((e) => e.value).reduce((a, b) => a + b) / recent.length;
    // Blend so one very bad day is not averaged away; monotonic in every log.
    final riskScore = (0.5 * latest + 0.5 * mean).clamp(0.0, 100.0).toDouble();

    final trend = _trend(scored);
    final daysSinceLast = now.difference(recent.first.key.timestamp).inHours / 24.0;

    final keyFactors = <String>[];
    final logs7 = recent.map((e) => e.key).toList();
    double avg(double? Function(DailyLog) f) {
      final vals = logs7.map(f).whereType<double>().where((v) => v.isFinite).toList();
      return vals.isEmpty ? double.nan : vals.reduce((a, b) => a + b) / vals.length;
    }

    if (avg((l) => l.moodScore) < 5) keyFactors.add('Low mood');
    final avgSleep = avg((l) => l.sleepHours);
    if (avgSleep < 6) keyFactors.add('Too little sleep');
    if (avgSleep > 10) keyFactors.add('Oversleeping');
    if (avg((l) => l.energyLevel) < 4) keyFactors.add('Low energy');
    if (anxietyRecorded && avg((l) => l.anxietyLevel) > 6.5) keyFactors.add('Elevated anxiety');
    if (latest >= 75) keyFactors.add('Latest check-in in critical range');
    if (daysSinceLast > staleAfterDays) {
      keyFactors.add('No check-in for ${daysSinceLast.floor()} days');
    }

    final step = trend == 'worsening' ? 1.5 : trend == 'improving' ? -1.2 : 0.0;
    final prediction7Days = List<double>.generate(
      7,
      (i) => (riskScore + step * (i + 1)).clamp(0.0, 100.0).toDouble(),
    );

    var confidence = min(0.9, 0.4 + recent.length * 0.07);
    if (daysSinceLast > staleAfterDays) confidence = max(0.2, confidence - 0.2);

    return RiskPrediction(
      riskScore: riskScore,
      riskLevel: riskLevelFor(riskScore),
      trend: trend,
      prediction7Days: prediction7Days,
      keyFactors: keyFactors.isEmpty ? ['No elevated factors in recent check-ins'] : keyFactors,
      confidence: confidence,
      source: 'firestore-daily-logs',
    );
  }

  /// Compare the mean of the 3 newest scored logs with the up-to-4 before them.
  static String _trend(List<MapEntry<DailyLog, double>> scoredNewestFirst) {
    if (scoredNewestFirst.length < 4) return 'stable';
    final newer = scoredNewestFirst.take(3).map((e) => e.value).toList();
    final older = scoredNewestFirst.skip(3).take(4).map((e) => e.value).toList();
    final delta = newer.reduce((a, b) => a + b) / newer.length - older.reduce((a, b) => a + b) / older.length;
    if (delta > 8) return 'worsening';
    if (delta < -8) return 'improving';
    return 'stable';
  }

  // ---------------------------------------------------------------------
  // Daily check-in scoring (for daily_checkin_screen.dart).
  // Choice ids match _moodOptions/_sleepOptions/_energyOptions there.
  // ---------------------------------------------------------------------

  /// Mood choice -> risk 0..1. The options are categorical, not ordinal:
  /// low mood is the core depressive symptom so 'sad' is NOT lower risk than
  /// 'frustrated' (the old (score-1)/4 mapping ranked sad 0.5 < frustrated 1.0).
  static const Map<String, double> checkInMoodRisk = {
    'great': 0.0,
    'okay': 0.33,
    'frustrated': 0.67,
    'anxious': 0.85,
    'sad': 1.0,
  };

  /// Sleep choice -> risk 0..1. 'too_much' (> 10 h; hypersomnia is part of
  /// PHQ-9 item 3) is supported for when the screen adds that option.
  static const Map<String, double> checkInSleepRisk = {
    'great': 0.0,
    'okay': 0.33,
    'too_much': 0.67,
    'poor': 0.67,
    'barely_slept': 1.0,
  };

  static const Map<String, double> checkInEnergyRisk = {
    'high': 0.0,
    'normal': 0.0,
    'low': 0.6,
    'drained': 1.0,
  };

  /// Check-in risk 0..100 = 40*mood + 30*sleep + 30*energy.
  /// Returns null if ANY answer is missing/unknown: never default a missing
  /// answer to the best value (the old code used `?? 1`, i.e. "great").
  static double? checkInRiskScore({String? moodId, String? sleepId, String? energyId}) {
    final m = checkInMoodRisk[moodId];
    final s = checkInSleepRisk[sleepId];
    final e = checkInEnergyRisk[energyId];
    if (m == null || s == null || e == null) return null;
    return (40 * m + 30 * s + 30 * e).clamp(0.0, 100.0).toDouble();
  }

  /// Whether the check-in should open the "are you safe?" prompt.
  /// Broader than the old `sad && drained && >= 2 worries` rule, which
  /// missed e.g. sad + barely slept, or anxious + drained.
  static bool checkInNeedsSafetyPrompt({
    String? moodId,
    String? sleepId,
    String? energyId,
    int worriesCount = 0,
    double? riskScore,
  }) {
    final lowMood = moodId == 'sad' || moodId == 'anxious';
    final depleted = energyId == 'drained' || sleepId == 'barely_slept';
    return (riskScore != null && riskScore >= 75) || (lowMood && depleted) || (lowMood && worriesCount >= 3);
  }
}
