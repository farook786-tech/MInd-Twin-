import 'package:flutter/foundation.dart';
import 'dart:math';
import 'daily_log_source.dart';
import 'ml_anomaly_service.dart';
import 'ml_risk_service.dart';
import '../models/daily_log.dart';

// DECISION SUPPORT ONLY. Per-log risk comes from MlRiskService.logRisk (the
// single documented, monotonic formula: mood/energy higher-is-better, sleep
// U-shaped around 7-9 h, missing values dropped). See docs/ML_SAFETY_EVALUATION.md.

/// Represents ML analysis results
class MentalHealthAnalysis {
  final double riskScore; // 0.0 - 1.0
  final String riskLevel; // Low, Moderate, High, Critical
  final double trendSlope; // -1.0 to 1.0 (negative = improving, positive = worsening)
  final String trendDirection; // Improving, Stable, Worsening
  final List<double> prediction; // Next 7 days risk prediction
  final bool anomalyDetected; // Unusual pattern detected
  final String anomalyDescription; // What's unusual
  final List<String> patterns; // Detected patterns (e.g., "Anxiety peaks on Mondays")
  final double wellbeingIndex; // 0.0 - 100.0
  final String recommendation; // AI-generated recommendation
  final Map<String, dynamic> detailedMetrics; // All calculated metrics

  MentalHealthAnalysis({
    required this.riskScore,
    required this.riskLevel,
    required this.trendSlope,
    required this.trendDirection,
    required this.prediction,
    required this.anomalyDetected,
    required this.anomalyDescription,
    required this.patterns,
    required this.wellbeingIndex,
    required this.recommendation,
    required this.detailedMetrics,
  });
}

/// ML-powered analysis for mental health trends and predictions
class MLAnalysisService {
  static final MLAnalysisService _instance = MLAnalysisService._internal();

  factory MLAnalysisService() {
    return _instance;
  }

  MLAnalysisService._internal();

  final _dailyLogSource = DailyLogSource();

  /// Analyze patient mental health data using ML algorithms
  Future<MentalHealthAnalysis> analyzePatientHealth(String userId) async {
    try {
      final logs = await _dailyLogSource.getDailyLogs(userId);

      if (logs.isEmpty) {
        return MentalHealthAnalysis(
          riskScore: 0.0,
          riskLevel: 'Insufficient Data',
          trendSlope: 0.0,
          trendDirection: 'No Data',
          prediction: [],
          anomalyDetected: false,
          anomalyDescription: 'Need at least one check-in',
          patterns: [],
          wellbeingIndex: 50.0,
          recommendation: 'Complete your first daily check-in to activate AI analysis',
          detailedMetrics: {},
        );
      }

      // Sort logs by date (newest first)
      final sortedLogs = logs.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Calculate metrics
      final currentRiskScore = _calculateRiskScore(sortedLogs);
      final trendAnalysis = _analyzeTrend(sortedLogs);
      final anomaly = _detectAnomalies(sortedLogs);
      final patterns = _detectPatterns(sortedLogs);
      final prediction = _predictNextWeek(sortedLogs);
      final riskLevel = _classifyRiskLevel(currentRiskScore);
      final wellbeingIndex = (1.0 - currentRiskScore) * 100.0;
      final recommendation = _generateRecommendation(
        currentRiskScore,
        trendAnalysis['slope'],
        anomaly['detected'],
        patterns,
      );

      return MentalHealthAnalysis(
        riskScore: currentRiskScore,
        riskLevel: riskLevel,
        trendSlope: trendAnalysis['slope'],
        trendDirection: trendAnalysis['direction'],
        prediction: prediction,
        anomalyDetected: anomaly['detected'],
        anomalyDescription: anomaly['description'],
        patterns: patterns,
        wellbeingIndex: wellbeingIndex,
        recommendation: recommendation,
        detailedMetrics: {
          'anxietyAverage': _average(_vals(sortedLogs, (l) => l.anxietyLevel, 10.0)),
          'moodAverage': _average(_vals(sortedLogs, (l) => l.moodScore, 10.0)),
          'sleepAverage': _average(_vals(sortedLogs, (l) => l.sleepHours, 12.0)),
          'wellbeingAverage': _average(_vals(sortedLogs, (l) => l.wellbeingScore, 100.0)),
          'stdDeviation': _standardDeviation(_vals(sortedLogs, (l) => l.anxietyLevel, 10.0)),
          'volatility': _calculateVolatility(sortedLogs),
          'dataPoints': sortedLogs.length,
        },
      );
    } catch (e) {
      debugPrint('Error in ML analysis: $e');
      rethrow;
    }
  }

  /// Per-log risk on a 0..1 scale (null when the log has no usable values).
  double? _logRisk01(DailyLog log) {
    final r = MlRiskService.logRisk(log);
    return r == null ? null : r / 100.0;
  }

  /// Risk scores for [logs] (newest first in, newest first out), dropping unusable logs.
  List<double> _riskSeriesNewestFirst(List<DailyLog> logs) =>
      logs.map(_logRisk01).whereType<double>().toList();

  /// Overall risk 0..1: mean of the 7 most recent usable logs.
  double _calculateRiskScore(List<DailyLog> logs) {
    final recent = _riskSeriesNewestFirst(logs).take(7).toList();
    if (recent.isEmpty) return 0.0;
    return (_average(recent)).clamp(0.0, 1.0);
  }

  /// Analyze trend using linear regression
  Map<String, dynamic> _analyzeTrend(List<DailyLog> logs) {
    if (logs.length < 2) {
      return {'slope': 0.0, 'direction': 'Insufficient Data'};
    }

    // Oldest -> newest so a positive slope means risk is rising.
    final riskScores = _riskSeriesNewestFirst(logs).reversed.toList();
    if (riskScores.length < 2) {
      return {'slope': 0.0, 'direction': 'Insufficient Data'};
    }

    // Linear regression
    final n = riskScores.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += riskScores[i];
      sumXY += i * riskScores[i];
      sumX2 += i * i;
    }

    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final direction =
        slope < -0.02 ? 'Improving' : (slope > 0.02 ? 'Worsening' : 'Stable');

    return {'slope': slope, 'direction': direction};
  }

  /// Detect anomalies: delegates to MlAnomalyService's baseline rules (the
  /// previous z-score used the OLDEST log as "latest" and anxietyLevel, which
  /// the check-in never records).
  Map<String, dynamic> _detectAnomalies(List<DailyLog> logs) {
    final result = MlAnomalyService.detectFromLogs(logs, now: DateTime.now());
    return {'detected': result.anomalyDetected, 'description': result.description};
  }

  /// Detect patterns in data (e.g., weekly cycles)
  List<String> _detectPatterns(List<DailyLog> logs) {
    final patterns = <String>[];

    if (logs.length < 7) {
      return patterns;
    }

    final sortedLogs = logs.toList();

    // Check for day-of-week pattern
    final dayOfWeekAnxiety = <int, List<double>>{};

    for (var log in sortedLogs.take(14)) {
      final dayOfWeek = log.timestamp.weekday;
      final anxiety = log.anxietyLevel;
      if (anxiety == null || !anxiety.isFinite) continue; // not recorded
      dayOfWeekAnxiety.putIfAbsent(dayOfWeek, () => []);
      dayOfWeekAnxiety[dayOfWeek]!.add(anxiety / 10.0);
    }

    // Find days with highest average anxiety
    double maxAnxiety = 0;
    int maxDay = 0;

    dayOfWeekAnxiety.forEach((day, anxieties) {
      final avg = _average(anxieties.toList());
      if (avg > maxAnxiety) {
        maxAnxiety = avg;
        maxDay = day;
      }
    });

    if (maxAnxiety > 0.6) {
      const dayNames = [
        '',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      patterns.add('📊 Anxiety peaks on ${dayNames[maxDay]}');
    }

    // Check for sleep pattern
    final sleepValues = _vals(sortedLogs.take(7), (l) => l.sleepHours, 12.0);
    final avgSleep = _average(sleepValues);

    if (sleepValues.isNotEmpty && avgSleep < 0.4) {
      patterns.add('😴 Poor sleep pattern - may impact anxiety');
    }

    // Check for mood improvement
    final recentMoods = _vals(sortedLogs.take(7), (l) => l.moodScore, 10.0);
    if (recentMoods.length >= 2 && recentMoods.first > recentMoods.last + 0.3) {
      patterns.add('😊 Your mood is improving!');
    }

    return patterns;
  }

  /// Predict risk for next 7 days using moving average
  List<double> _predictNextWeek(List<DailyLog> logs) {
    if (logs.isEmpty) return [];

    final riskScores = _riskSeriesNewestFirst(logs);
    if (riskScores.isEmpty) return [];

    final trendAnalysis = _analyzeTrend(logs);
    final slope = trendAnalysis['slope'] as double;
    // Newest log (the old code reversed the list and extrapolated from the oldest).
    final lastRisk = riskScores.first;

    final prediction = <double>[];

    for (int i = 1; i <= 7; i++) {
      var predictedRisk = lastRisk + (slope * i);
      predictedRisk = predictedRisk.clamp(0.0, 1.0);
      prediction.add(predictedRisk);
    }

    return prediction;
  }

  /// Classify risk level based on score
  String _classifyRiskLevel(double score) {
    // Same bands as MlRiskService.riskLevelFor (25/50/75 on 0..100).
    if (score < 0.25) return 'Low';
    if (score < 0.5) return 'Moderate';
    if (score < 0.75) return 'High';
    return 'Critical';
  }

  /// Generate AI recommendation
  String _generateRecommendation(
    double riskScore,
    double trendSlope,
    bool anomalyDetected,
    List<String> patterns,
  ) {
    if (riskScore >= 0.75) {
      return '⚠️ Recent check-ins are in the critical range. Please reach out to your therapist or a crisis line.';
    } else if (riskScore > 0.6 && trendSlope > 0.02) {
      return '⚠️ Your check-ins are getting worse quickly. Consider reaching out to your therapist.';
    } else if (riskScore > 0.6) {
      return '💭 Recent check-ins show high strain. Try grounding techniques and tell your therapist.';
    } else if (trendSlope > 0.02) {
      return '📈 Your check-ins are trending worse. Monitor your stressors.';
    } else if (trendSlope < -0.02) {
      return '✨ Great progress! Your check-ins are improving.';
    } else if (anomalyDetected) {
      return '🔔 Unusual pattern detected. Reflect on what might have caused this change.';
    } else if (patterns.isEmpty) {
      return '✅ You\'re stable. Keep maintaining your wellness routine.';
    } else {
      return '📊 Identified patterns. Use this insight to manage your triggers.';
    }
  }

  /// Helper: Calculate average
  /// Recorded (non-null, finite) values of [f] divided by [div]; missing
  /// values are skipped, never replaced by a default.
  static List<double> _vals(Iterable<DailyLog> logs, double? Function(DailyLog) f, double div) =>
      logs.map(f).whereType<double>().where((v) => v.isFinite).map((v) => v / div).toList();

  double _average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Helper: Calculate standard deviation
  double _standardDeviation(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = _average(values);
    final variance = _average(values.map((x) => (x - mean) * (x - mean)).toList());
    return variance.isNaN ? 0.0 : sqrt(variance);
  }

  /// Helper: Calculate volatility (measure of variability)
  double _calculateVolatility(List<DailyLog> logs) {
    if (logs.length < 2) return 0.0;

    final riskScores = _riskSeriesNewestFirst(logs);
    if (riskScores.length < 2) return 0.0;

    double sumSquaredDiff = 0;
    for (int i = 1; i < riskScores.length; i++) {
      final diff = riskScores[i] - riskScores[i - 1];
      sumSquaredDiff += diff * diff;
    }

    return sqrt(sumSquaredDiff / (riskScores.length - 1));
  }
}
