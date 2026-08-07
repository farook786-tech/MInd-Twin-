import 'daily_log_source.dart';

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

  Future<AnomalyResult> detectAnomaly(String patientId) async {
    try {
      final logs = await _dailyLogSource.getDailyLogs(patientId);
      if (logs.length < 3) {
        return const AnomalyResult(
          anomalyDetected: false,
          anomalyType: 'insufficient_data',
          severity: 'low',
          description: 'Need more daily logs to detect anomalies.',
          recommendation: 'Continue regular check-ins to build a baseline.',
          confidence: 0.35,
        );
      }

      final recent = logs.take(5).toList();
      final anxietyValues = recent.map((log) => log.anxietyLevel).toList();
      final moodValues = recent.map((log) => log.moodScore).toList();
      final latestAnxiety = anxietyValues.first;
      final avgAnxiety = _average(anxietyValues);
      final moodDrop = moodValues.length > 1 && moodValues.first <= moodValues.last - 2;

      final anxietySpike = latestAnxiety >= avgAnxiety + 3;
      if (!anxietySpike && !moodDrop) {
        return const AnomalyResult(
          anomalyDetected: false,
          anomalyType: 'none',
          severity: 'low',
          description: 'No unusual pattern detected in recent logs.',
          recommendation: 'Maintain the current routine and continue tracking.',
          confidence: 0.6,
        );
      }

      return AnomalyResult(
        anomalyDetected: true,
        anomalyType: anxietySpike ? 'anxiety_spike' : 'mood_drop',
        severity: anxietySpike && moodDrop ? 'high' : 'moderate',
        description: anxietySpike
            ? 'A recent anxiety spike stands out from the recent baseline.'
            : 'A downward mood pattern appears in the latest logs.',
        recommendation: 'Reach out to the care team and consider immediate coping support.',
        confidence: anxietySpike && moodDrop ? 0.88 : 0.74,
      );
    } catch (_) {
      return const AnomalyResult(
        anomalyDetected: false,
        anomalyType: 'fallback',
        severity: 'low',
        description: 'Anomaly detection unavailable right now.',
        recommendation: 'Try again after more logs are available.',
        confidence: 0.3,
      );
    }
  }

  double _average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}