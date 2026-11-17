import 'dart:math';

import '../models/daily_log.dart';
import 'daily_log_source.dart';
import 'ml_risk_service.dart';

// DECISION SUPPORT ONLY: anomalies prompt a therapist to look; they are not
// diagnoses. Evaluation: docs/ML_SAFETY_EVALUATION.md.
//
// Design (fixes over the previous version):
//  * Uses the shared per-log risk (MlRiskService.logRisk) instead of
//    anxietyLevel, which the check-in never records (it was always the
//    DailyLogSource default 5.0, so an "anxiety spike" could never fire).
//  * Baseline = logs from the 28 days before the latest log; a deviation
//    anomaly needs >= 4 baseline points, and the spread is floored at 8 risk
//    points so 3-4 near-identical logs cannot turn a small change into a
//    false alarm (old rule: any 2-point mood dip on a 0-10 scale, which one
//    step "great" -> "okay" (2.5 points) already triggered).
//  * Safety rules that do NOT need a baseline: a critical latest check-in
//    (risk >= 75) is always reported, and 7+ days without a check-in is
//    reported as disengagement (a recognised risk signal), never silently.

class AnomalyResult {
  final bool anomalyDetected;
  final String anomalyType;
  final String severity;
  final String description;
  final String recommendation;
  final double confidence;

  const AnomalyResult({
    required this.anomalyDetected,
    required this.anomalyType,
    required this.severity,
    required this.description,
    required this.recommendation,
    required this.confidence,
  });
}

class MlAnomalyService {
  final DailyLogSource _dailyLogSource = DailyLogSource();

  static const int minBaselinePoints = 4;
  static const int baselineWindowDays = 28;
  static const double minSpread = 8.0;
  static const double zThreshold = 2.0;
  static const double minAbsoluteRise = 15.0;
  static const int disengagedAfterDays = 7;

  Future<AnomalyResult> detectAnomaly(String patientId) async {
    final logs = await _dailyLogSource.getDailyLogs(patientId);
    return detectFromLogs(logs, now: DateTime.now());
  }

  static AnomalyResult detectFromLogs(List<DailyLog> logs, {required DateTime now}) {
    final scored = <MapEntry<DailyLog, double>>[];
    for (final log in logs.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp))) {
      final r = MlRiskService.logRisk(log);
      if (r != null) scored.add(MapEntry(log, r));
    }
    if (scored.isEmpty) {
      return const AnomalyResult(
        anomalyDetected: false,
        anomalyType: 'insufficient_data',
        severity: 'low',
        description: 'No usable check-ins yet.',
        recommendation: 'Continue regular check-ins to build a baseline.',
        confidence: 0.0,
      );
    }

    final latest = scored.first;
    final daysSince = now.difference(latest.key.timestamp).inHours / 24.0;

    if (latest.value >= 75 && daysSince <= disengagedAfterDays) {
      return AnomalyResult(
        anomalyDetected: true,
        anomalyType: 'acute_high_risk',
        severity: 'high',
        description: 'The latest check-in is in the critical range (risk ${latest.value.toStringAsFixed(0)}/100).',
        recommendation: 'Care team should review today; offer safety resources.',
        confidence: 0.8,
      );
    }

    if (daysSince > disengagedAfterDays) {
      return AnomalyResult(
        anomalyDetected: true,
        anomalyType: 'missed_checkins',
        severity: 'moderate',
        description: 'No check-in for ${daysSince.floor()} days.',
        recommendation: 'Reach out to the patient; disengagement can precede deterioration.',
        confidence: 0.6,
      );
    }

    final windowStart = latest.key.timestamp.subtract(const Duration(days: baselineWindowDays));
    final baseline = scored
        .skip(1)
        .where((e) => !e.key.timestamp.isBefore(windowStart))
        .map((e) => e.value)
        .toList();
    if (baseline.length < minBaselinePoints) {
      return AnomalyResult(
        anomalyDetected: false,
        anomalyType: 'insufficient_data',
        severity: 'low',
        description: 'Need at least $minBaselinePoints check-ins in the last $baselineWindowDays days '
            'to compare against (have ${baseline.length}).',
        recommendation: 'Continue regular check-ins to build a baseline.',
        confidence: 0.3,
      );
    }

    final mean = baseline.reduce((a, b) => a + b) / baseline.length;
    final variance = baseline.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / baseline.length;
    final spread = max(minSpread, sqrt(variance));
    final rise = latest.value - mean;
    final z = rise / spread;

    if (z >= zThreshold && rise >= minAbsoluteRise) {
      final severe = z >= 3 || latest.value >= 60;
      return AnomalyResult(
        anomalyDetected: true,
        anomalyType: 'risk_spike',
        severity: severe ? 'high' : 'moderate',
        description: 'Latest check-in risk ${latest.value.toStringAsFixed(0)} is well above this '
            'patient\'s recent baseline ${mean.toStringAsFixed(0)} (z=${z.toStringAsFixed(1)}).',
        recommendation: 'Reach out to the care team and consider immediate coping support.',
        confidence: min(0.9, 0.5 + baseline.length * 0.04),
      );
    }

    return AnomalyResult(
      anomalyDetected: false,
      anomalyType: 'none',
      severity: 'low',
      description: 'Latest check-in is within this patient\'s recent range.',
      recommendation: 'Maintain the current routine and continue tracking.',
      confidence: min(0.85, 0.4 + baseline.length * 0.04),
    );
  }
}
