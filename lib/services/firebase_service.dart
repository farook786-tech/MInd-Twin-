import '../models/patient.dart';
import '../models/daily_log.dart';
import '../models/intervention.dart';
import '../models/crisis_alert.dart';

/// Firebase Service with Real-Time StreamBuilders
/// Implements the 'Digital Twin Engine' for predictive risk scoring
/// DEMO MODE: Uses mock data instead of Firebase
class FirebaseService {
  // Demo mode - no Firebase connection
  // All methods return mock data or streams

  // ==================== PATIENT OPERATIONS ====================

  /// Real-time stream of all patients (DEMO MODE)
  Stream<List<Patient>> getPatientsStream() {
    return Stream.periodic(const Duration(seconds: 1), (_) {
      return [Patient.demoJamesK()];
    });
  }

  /// Real-time stream of a single patient (DEMO MODE)
  Stream<Patient?> getPatientStream(String patientId) {
    return Stream.periodic(const Duration(seconds: 1), (_) {
      return Patient.demoJamesK();
    });
  }

  /// Get patients for a specific therapist (DEMO MODE)
  Stream<List<Patient>> getTherapistPatientsStream(String therapistId) {
    return Stream.periodic(const Duration(seconds: 1), (_) {
      return [Patient.demoJamesK()];
    });
  }

  /// Update patient data (DEMO MODE)
  Future<void> updatePatient(Patient patient) async {
    // Mock update - no actual storage
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ==================== DAILY LOG OPERATIONS ====================

  /// Real-time stream of daily logs for a patient (DEMO MODE)
  Stream<List<DailyLog>> getPatientDailyLogsStream(String patientId) {
    return Stream.periodic(const Duration(seconds: 1), (_) {
      return List.generate(7, (index) {
        return DailyLog(
          id: 'demo_log_$index',
          patientId: patientId,
          timestamp: DateTime.now().subtract(Duration(days: 6 - index)),
          moodScore: 5.0 + (index * 0.5),
          sleepHours: 7.0 + (index * 0.2),
          energyLevel: 5.0 + (index * 0.4),
          wellbeingScore: 0.5 + (index * 0.05),
        );
      });
    });
  }

  /// Submit a daily check-in (DEMO MODE)
  Future<void> submitDailyLog(DailyLog log) async {
    // Calculate wellbeing score using Digital Twin Engine
    final wellbeingScore = calculateWellbeingScore(log);
    // Mock submission - no actual storage
    await Future.delayed(const Duration(milliseconds: 500));
    print('Demo: Wellbeing score calculated: $wellbeingScore');
  }

  /// Digital Twin Engine: Weights 5 signals
  /// 1. Voice energy (20%)
  /// 2. Text sentiment (20%)
  /// 3. Sleep (20%)
  /// 4. Self-report (mood + energy) (30%)
  /// 5. Passive behavior (app frequency) (10%)
  double calculateWellbeingScore(DailyLog log) {
    // Voice energy: 0-1 scale (already normalized)
    final voiceScore = log.voiceEnergy;

    // Text sentiment: -1 to 1, normalize to 0-1
    final sentimentScore = (log.textSentiment + 1) / 2;

    // Sleep: 0-12 hours, optimal around 7-8
    final sleepScore = _calculateSleepScore(log.sleepHours);

    // Self-report: mood (0-10) + energy (0-10), average and normalize
    final selfReportScore = ((log.moodScore + log.energyLevel) / 2) / 10;

    // Passive behavior: app opens (normalize, more opens = more engaged)
    final behaviorScore = _calculateBehaviorScore(log.appOpenCount);

    // Weighted sum
    final wellbeingScore = (voiceScore * 0.20) +
        (sentimentScore * 0.20) +
        (sleepScore * 0.20) +
        (selfReportScore * 0.30) +
        (behaviorScore * 0.10);

    return wellbeingScore.clamp(0.0, 1.0);
  }

  double _calculateSleepScore(double hours) {
    // Optimal sleep: 7-8 hours = 1.0
    // Too little or too much = lower score
    if (hours >= 7 && hours <= 8) return 1.0;
    if (hours >= 6 && hours <= 9) return 0.8;
    if (hours >= 5 && hours <= 10) return 0.6;
    if (hours >= 4 && hours <= 11) return 0.4;
    return 0.2;
  }

  double _calculateBehaviorScore(int appOpenCount) {
    // 3-5 opens per day = healthy engagement
    if (appOpenCount >= 3 && appOpenCount <= 5) return 1.0;
    if (appOpenCount >= 2 && appOpenCount <= 7) return 0.8;
    if (appOpenCount >= 1 && appOpenCount <= 10) return 0.6;
    if (appOpenCount == 0) return 0.3; // Very low engagement
    return 0.5; // Too many opens
  }

  // ==================== INTERVENTION OPERATIONS ====================

  /// Real-time stream of interventions for a patient (DEMO MODE)
  Stream<List<Intervention>> getPatientInterventionsStream(String patientId) {
    return Stream.periodic(const Duration(seconds: 1), (_) => <Intervention>[]);
  }

  /// Create an intervention (DEMO MODE)
  Future<void> createIntervention(Intervention intervention) async {
    await Future.delayed(const Duration(milliseconds: 500));
    print('Demo: Intervention created: ${intervention.description}');
  }

  /// Simulate intervention impact on risk trajectory
  List<Map<String, dynamic>> simulateIntervention(
    List<DailyLog> historicalLogs,
    InterventionType interventionType,
    double currentRisk,
  ) {
    final riskReduction = Intervention.riskReductionConstants[interventionType] ?? 0.0;
    final projectedTrajectory = <Map<String, dynamic>>[];

    // Current trajectory (baseline - no intervention)
    for (int i = 0; i < 30; i++) {
      final date = DateTime.now().add(Duration(days: i));
      final naturalDecay = currentRisk * (1 - (i * 0.005)); // Slight natural improvement
      projectedTrajectory.add({
        'date': date,
        'baselineRisk': naturalDecay.clamp(0.0, 1.0),
        'interventionRisk': (naturalDecay * (1 - riskReduction)).clamp(0.0, 1.0),
      });
    }

    return projectedTrajectory;
  }

  // ==================== CRISIS ALERT OPERATIONS ====================

  /// Real-time stream of crisis alerts (DEMO MODE)
  Stream<List<CrisisAlert>> getActiveCrisisAlertsStream() {
    return Stream.periodic(const Duration(seconds: 1), (_) => <CrisisAlert>[]);
  }

  /// Trigger SOS - Create crisis alert (DEMO MODE)
  Future<void> triggerCrisisAlert(String patientId, String patientName) async {
    await Future.delayed(const Duration(milliseconds: 500));
    print('Demo: SOS triggered for $patientName');
  }

  /// Acknowledge a crisis alert (DEMO MODE)
  Future<void> acknowledgeCrisisAlert(String alertId, String therapistId, String notes) async {
    await Future.delayed(const Duration(milliseconds: 500));
    print('Demo: Crisis alert acknowledged');
  }

  // ==================== ANALYTICS & OPTIMAL TIMING ====================

  /// Calculate best contact window (DEMO MODE)
  Future<String> getBestContactWindow(String patientId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 'Morning (09:00)';
  }
}
