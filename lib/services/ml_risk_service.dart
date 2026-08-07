import 'dart:math';

import '../models/daily_log.dart';
import 'daily_log_source.dart';

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

  Future<RiskPrediction> predictRisk(String patientId) async {
    try {
      final logs = await _dailyLogSource.getDailyLogs(patientId);
      if (logs.isEmpty) {
        return const RiskPrediction(
          riskScore: 35,
          riskLevel: 'moderate',
          trend: 'stable',
          prediction7Days: [35, 35, 36, 36, 37, 37, 38],
          keyFactors: ['Insufficient check-in history'],
          confidence: 0.45,
          source: 'local-fallback',
        );
      }

      final recent = logs.take(7).toList();
      final avgMood = _average(recent.map((log) => log.moodScore / 10.0));
      final avgSleep = _average(recent.map((log) => log.sleepHours / 12.0));
      final avgAnxiety = _average(recent.map((log) => log.anxietyLevel / 10.0));
      final avgWellbeing = _average(recent.map((log) => log.wellbeingScore / 100.0));

      final riskScore = ((1 - avgMood) * 30) + ((1 - avgSleep) * 20) + (avgAnxiety * 30) + ((1 - avgWellbeing) * 20);
      final normalizedRisk = riskScore.clamp(0.0, 100.0);
      final trend = _trendFromLogs(recent);
      final riskLevel = _riskLevel(normalizedRisk);

      final keyFactors = <String>[];
      if (avgMood < 0.5) keyFactors.add('Low mood');
      if (avgSleep < 0.55) keyFactors.add('Poor sleep');
      if (avgAnxiety > 0.65) keyFactors.add('Elevated anxiety');
      if (avgWellbeing < 0.55) keyFactors.add('Lower wellbeing');

      final prediction7Days = List<double>.generate(
        7,
        (index) => (normalizedRisk + (trend == 'worsening' ? index * 1.5 : trend == 'improving' ? -index * 1.2 : index * 0.3))
            .clamp(0.0, 100.0),
      );

      return RiskPrediction(
        riskScore: normalizedRisk,
        riskLevel: riskLevel,
        trend: trend,
        prediction7Days: prediction7Days,
        keyFactors: keyFactors.isEmpty ? ['Check-in pattern available'] : keyFactors,
        confidence: min(0.95, 0.55 + (recent.length * 0.05)),
        source: 'firestore-daily-logs',
      );
    } catch (_) {
      return const RiskPrediction(
        riskScore: 40,
        riskLevel: 'moderate',
        trend: 'stable',
        prediction7Days: [40, 40, 41, 41, 42, 42, 43],
        keyFactors: ['Fallback risk estimate'],
        confidence: 0.4,
        source: 'local-fallback',
      );
    }
  }

  String _riskLevel(double score) {
    if (score >= 75) return 'critical';
    if (score >= 50) return 'high';
    if (score >= 25) return 'moderate';
    return 'low';
  }

  String _trendFromLogs(List<DailyLog> logs) {
    if (logs.length < 2) return 'stable';
    final latest = _logRisk(logs.first);
    final oldest = _logRisk(logs.last);
    final delta = latest - oldest;
    if (delta > 8) return 'worsening';
    if (delta < -8) return 'improving';
    return 'stable';
  }

  double _logRisk(DailyLog log) {
    return (((1 - (log.moodScore / 10.0)) * 40) +
            ((1 - (log.sleepHours / 12.0)) * 25) +
            ((log.anxietyLevel / 10.0) * 25) +
            ((1 - (log.wellbeingScore / 100.0)) * 10))
        .clamp(0.0, 100.0);
  }

  double _average(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return 0.0;
    return list.reduce((a, b) => a + b) / list.length;
  }
}