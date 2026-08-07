import 'package:flutter/foundation.dart';
import 'dart:math';
import 'daily_log_source.dart';
import '../models/daily_log.dart';

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
      final sortedLogs = logs.toList();

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
          'anxietyAverage': _average(sortedLogs.map((l) => l.anxietyLevel / 10.0).toList()),
          'moodAverage': _average(sortedLogs.map((l) => l.moodScore / 10.0).toList()),
          'sleepAverage': _average(sortedLogs.map((l) => l.sleepHours / 12.0).toList()),
          'wellbeingAverage': _average(sortedLogs.map((l) => l.wellbeingScore / 100.0).toList()),
          'stdDeviation': _standardDeviation(sortedLogs.map((l) => l.anxietyLevel / 10.0).toList()),
          'volatility': _calculateVolatility(sortedLogs),
          'dataPoints': sortedLogs.length,
        },
      );
    } catch (e) {
      debugPrint('Error in ML analysis: $e');
      rethrow;
    }
  }

  /// Calculate overall risk score using weighted metrics (0.0 - 1.0)
  double _calculateRiskScore(List<DailyLog> logs) {
    if (logs.isEmpty) return 0.0;

    final recentLogs = logs.take(7).toList();

    double totalRisk = 0.0;

    for (var log in recentLogs) {
      // Normalize values to 0-1
      double anxiety = (log.anxietyLevel / 10.0).clamp(0.0, 1.0);
      double mood = (1.0 - (log.moodScore / 10.0)).clamp(0.0, 1.0);
      double sleep = (1.0 - (log.sleepHours / 12.0)).clamp(0.0, 1.0);
      double wellbeing = (1.0 - (log.wellbeingScore / 100.0)).clamp(0.0, 1.0);

      // Weighted calculation
      double logRisk = (anxiety * 0.4 + mood * 0.30 + sleep * 0.15 + wellbeing * 0.15);

      totalRisk += logRisk;
    }

    return (totalRisk / recentLogs.length).clamp(0.0, 1.0);
  }

  /// Analyze trend using linear regression
  Map<String, dynamic> _analyzeTrend(List<DailyLog> logs) {
    if (logs.length < 2) {
      return {'slope': 0.0, 'direction': 'Insufficient Data'};
    }

    final riskScores = logs
        .map((log) {
          double anxiety = (log.anxietyLevel / 10.0).clamp(0.0, 1.0);
          double mood = (1.0 - (log.moodScore / 10.0)).clamp(0.0, 1.0);
          return (anxiety * 0.6 + mood * 0.4);
        })
        .toList()
        .reversed
        .toList();

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

  /// Detect anomalies using statistical methods (z-score)
  Map<String, dynamic> _detectAnomalies(List<DailyLog> logs) {
    if (logs.length < 3) {
      return {'detected': false, 'description': 'Insufficient data for anomaly detection'};
    }

    final anxietyValues =
        logs.map((l) => l.anxietyLevel / 10.0).toList().reversed.toList();

    final mean = _average(anxietyValues);
    final stdDev = _standardDeviation(anxietyValues.toList());

    if (stdDev == 0) {
      return {'detected': false, 'description': 'All values are consistent'};
    }

    // Check if latest value is anomalous (z-score > 2)
    final latestAnxiety = anxietyValues.first;
    final zScore = (latestAnxiety - mean) / stdDev;

    if (zScore.abs() > 2.0) {
      return {
        'detected': true,
        'description': zScore > 0
            ? 'Anxiety spike detected! This is unusually high for you.'
            : 'Unusual calm detected - great improvement!'
      };
    }

    return {'detected': false, 'description': 'Within normal range for your pattern'};
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
      dayOfWeekAnxiety.putIfAbsent(dayOfWeek, () => []);
      dayOfWeekAnxiety[dayOfWeek]!.add(log.anxietyLevel / 10.0);
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
    final sleepValues = sortedLogs.take(7).map((l) => l.sleepHours / 12.0).toList();
    final avgSleep = _average(sleepValues);

    if (avgSleep < 0.4) {
      patterns.add('😴 Poor sleep pattern - may impact anxiety');
    }

    // Check for mood improvement
    final recentMoods = sortedLogs.take(7).map((l) => l.moodScore / 10.0).toList();
    if (recentMoods.first > recentMoods.last + 0.3) {
      patterns.add('😊 Your mood is improving!');
    }

    return patterns;
  }

  /// Predict risk for next 7 days using moving average
  List<double> _predictNextWeek(List<DailyLog> logs) {
    if (logs.isEmpty) return [];

    final riskScores = logs
        .map((log) {
          double anxiety = (log.anxietyLevel / 10.0).clamp(0.0, 1.0);
          double mood = (1.0 - (log.moodScore / 10.0)).clamp(0.0, 1.0);
          return (anxiety * 0.6 + mood * 0.4);
        })
        .toList()
        .reversed
        .toList();

    final trendAnalysis = _analyzeTrend(logs);
    final slope = trendAnalysis['slope'] as double;
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
    if (score < 0.2) return 'Low';
    if (score < 0.4) return 'Moderate';
    if (score < 0.7) return 'High';
    return 'Critical';
  }

  /// Generate AI recommendation
  String _generateRecommendation(
    double riskScore,
    double trendSlope,
    bool anomalyDetected,
    List<String> patterns,
  ) {
    if (riskScore > 0.7 && trendSlope > 0.02) {
      return '⚠️ Your anxiety is increasing rapidly. Consider reaching out to your therapist.';
    } else if (riskScore > 0.6) {
      return '💭 High anxiety detected. Try grounding techniques or mindfulness exercises.';
    } else if (trendSlope > 0.02) {
      return '📈 Your anxiety is trending upward. Monitor your stressors.';
    } else if (trendSlope < -0.02) {
      return '✨ Great progress! Your anxiety is improving.';
    } else if (anomalyDetected) {
      return '🔔 Unusual pattern detected. Reflect on what might have caused this change.';
    } else if (patterns.isEmpty) {
      return '✅ You\'re stable. Keep maintaining your wellness routine.';
    } else {
      return '📊 Identified patterns. Use this insight to manage your triggers.';
    }
  }

  /// Helper: Calculate average
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

    final riskScores = logs
        .map((log) {
          double anxiety = (log.anxietyLevel / 10.0).clamp(0.0, 1.0);
          double mood = (1.0 - (log.moodScore / 10.0)).clamp(0.0, 1.0);
          return (anxiety * 0.6 + mood * 0.4);
        })
        .toList();

    double sumSquaredDiff = 0;
    for (int i = 1; i < riskScores.length; i++) {
      final diff = riskScores[i] - riskScores[i - 1];
      sumSquaredDiff += diff * diff;
    }

    return sqrt(sumSquaredDiff / (riskScores.length - 1));
  }
}
