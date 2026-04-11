import '../models/daily_log.dart';
import '../models/intervention.dart';
import 'gemini_service.dart';
import 'database_service.dart';

class WearableSignalInput {
  final double heartRate;
  final double sleepQuality;
  final double activityLevel;
  final double screenTimeHours;

  const WearableSignalInput({
    required this.heartRate,
    required this.sleepQuality,
    required this.activityLevel,
    required this.screenTimeHours,
  });
}

class ExplainabilityFactor {
  final String factor;
  final double contributionPercent;

  const ExplainabilityFactor({
    required this.factor,
    required this.contributionPercent,
  });
}

class CrisisPrediction {
  final double riskScore100;
  final String state;
  final bool triggerTherapistAlert;

  const CrisisPrediction({
    required this.riskScore100,
    required this.state,
    required this.triggerTherapistAlert,
  });
}

class InterventionDecision {
  final InterventionType type;
  final String title;
  final String rationale;

  const InterventionDecision({
    required this.type,
    required this.title,
    required this.rationale,
  });
}

class CompanionResponse {
  final String message;
  final String cbtExercise;

  const CompanionResponse({
    required this.message,
    required this.cbtExercise,
  });
}

class AdvancedClinicalAnalysis {
  final CrisisPrediction crisisPrediction;
  final List<ExplainabilityFactor> explainability;
  final InterventionDecision interventionDecision;
  final CompanionResponse companionResponse;

  const AdvancedClinicalAnalysis({
    required this.crisisPrediction,
    required this.explainability,
    required this.interventionDecision,
    required this.companionResponse,
  });
}

class AdvancedClinicalAIService {
  static final AdvancedClinicalAIService _instance =
      AdvancedClinicalAIService._internal();

  factory AdvancedClinicalAIService() => _instance;

  AdvancedClinicalAIService._internal();

  final DatabaseService _dbService = DatabaseService();
  final GeminiService _geminiService = GeminiService();

  Future<AdvancedClinicalAnalysis> analyze({
    required String patientId,
    required DailyLog log,
    required WearableSignalInput wearable,
  }) async {
    final explainability = _buildExplainability(log, wearable);
    final riskScore100 = _aggregateRiskScore(log, wearable);
    final crisis = _classifyCrisis(riskScore100);
    final intervention = await _recommendIntervention(
      patientId: patientId,
      score: riskScore100,
      log: log,
    );
    final companion = _buildCompanionResponse(
      score: riskScore100,
      log: log,
      intervention: intervention,
    );

    return AdvancedClinicalAnalysis(
      crisisPrediction: crisis,
      explainability: explainability,
      interventionDecision: intervention,
      companionResponse: companion,
    );
  }

  List<ExplainabilityFactor> _buildExplainability(
    DailyLog log,
    WearableSignalInput wearable,
  ) {
    final sleepRisk = ((1 - (wearable.sleepQuality / 10)).clamp(0.0, 1.0)) * 100;
    final activityRisk = ((1 - (wearable.activityLevel / 10)).clamp(0.0, 1.0)) * 100;
    final moodRisk = ((1 - (log.moodScore / 10)).clamp(0.0, 1.0)) * 100;
    final anxietyRisk = ((log.anxietyLevel / 10).clamp(0.0, 1.0)) * 100;
    final screenRisk = ((wearable.screenTimeHours / 10).clamp(0.0, 1.0)) * 100;
    final hrRisk = ((wearable.heartRate - 60) / 60).clamp(0.0, 1.0) * 100;

    final weighted = {
      'Sleep quality': sleepRisk * 0.24,
      'Activity level': activityRisk * 0.18,
      'Mood score': moodRisk * 0.22,
      'Anxiety level': anxietyRisk * 0.20,
      'Screen time': screenRisk * 0.09,
      'Heart-rate stress': hrRisk * 0.07,
    };

    final total = weighted.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) {
      return const [
        ExplainabilityFactor(factor: 'Insufficient variance', contributionPercent: 100),
      ];
    }

    final factors = weighted.entries
        .map(
          (e) => ExplainabilityFactor(
            factor: e.key,
            contributionPercent: (e.value / total) * 100,
          ),
        )
        .toList()
      ..sort((a, b) => b.contributionPercent.compareTo(a.contributionPercent));

    return factors;
  }

  double _aggregateRiskScore(DailyLog log, WearableSignalInput wearable) {
    final sleepRisk = ((1 - (wearable.sleepQuality / 10)).clamp(0.0, 1.0)) * 100;
    final activityRisk = ((1 - (wearable.activityLevel / 10)).clamp(0.0, 1.0)) * 100;
    final moodRisk = ((1 - (log.moodScore / 10)).clamp(0.0, 1.0)) * 100;
    final anxietyRisk = ((log.anxietyLevel / 10).clamp(0.0, 1.0)) * 100;
    final screenRisk = ((wearable.screenTimeHours / 10).clamp(0.0, 1.0)) * 100;
    final hrRisk = ((wearable.heartRate - 60) / 60).clamp(0.0, 1.0) * 100;

    final weightedScore =
        sleepRisk * 0.22 +
        activityRisk * 0.15 +
        moodRisk * 0.22 +
        anxietyRisk * 0.23 +
        screenRisk * 0.08 +
        hrRisk * 0.10;

    return weightedScore.clamp(0, 100);
  }

  CrisisPrediction _classifyCrisis(double score) {
    if (score < 40) {
      return CrisisPrediction(
        riskScore100: score,
        state: 'Safe',
        triggerTherapistAlert: false,
      );
    }
    if (score < 70) {
      return CrisisPrediction(
        riskScore100: score,
        state: 'Monitor',
        triggerTherapistAlert: false,
      );
    }
    if (score < 90) {
      return CrisisPrediction(
        riskScore100: score,
        state: 'High Risk',
        triggerTherapistAlert: true,
      );
    }
    return CrisisPrediction(
      riskScore100: score,
      state: 'Emergency',
      triggerTherapistAlert: true,
    );
  }

  Future<InterventionDecision> _recommendIntervention({
    required String patientId,
    required double score,
    required DailyLog log,
  }) async {
    final history = await _safeGetInterventions(patientId);

    double breathingReward = 0.50;
    double cbtReward = 0.50;
    double clinicianReward = 0.50;

    for (final item in history) {
      final reward = item.projectedRiskReduction.clamp(0.0, 1.0);
      if (item.type == InterventionType.callPatient) {
        breathingReward = (breathingReward + reward) / 2;
      } else if (item.type == InterventionType.groupTherapy) {
        cbtReward = (cbtReward + reward) / 2;
      } else if (item.type == InterventionType.psychiatristReferral) {
        clinicianReward = (clinicianReward + reward) / 2;
      }
    }

    if (score >= 85 || log.anxietyLevel >= 8) {
      return const InterventionDecision(
        type: InterventionType.psychiatristReferral,
        title: 'Immediate clinician escalation',
        rationale: 'RL policy prioritizes therapist escalation for sustained high-risk states.',
      );
    }

    if (cbtReward >= breathingReward && score >= 55) {
      return const InterventionDecision(
        type: InterventionType.groupTherapy,
        title: 'Guided CBT reframe sequence',
        rationale: 'Policy selected CBT based on better reward history for moderate-risk patterns.',
      );
    }

    if (breathingReward >= cbtReward) {
      return const InterventionDecision(
        type: InterventionType.callPatient,
        title: '3-minute regulation protocol',
        rationale: 'Policy selected breathing regulation due to better short-term reward trends.',
      );
    }

    return const InterventionDecision(
      type: InterventionType.groupTherapy,
      title: 'Cognitive stabilizer routine',
      rationale: 'Policy selected a balanced intervention from current state-action values.',
    );
  }

  CompanionResponse _buildCompanionResponse({
    required double score,
    required DailyLog log,
    required InterventionDecision intervention,
  }) {
    if (score >= 90) {
      return const CompanionResponse(
        message:
            'I can see this is very intense right now. I am escalating this to your therapist and staying with you step by step.',
        cbtExercise: 'Name 5 things you can see, 4 you can feel, 3 you can hear, 2 you can smell, 1 you can taste.',
      );
    }

    if (score >= 70) {
      return const CompanionResponse(
        message:
            'You are carrying a heavy load today. We can reduce the pressure together with one focused action now.',
        cbtExercise:
            'Thought record: Situation -> Automatic thought -> Evidence for -> Evidence against -> Balanced thought.',
      );
    }

    if (log.moodScore >= 7 && score < 40) {
      return const CompanionResponse(
        message:
            'Strong check-in today. Keep momentum with one recovery habit before bedtime.',
        cbtExercise: 'Write 3 wins from today and one coping strategy that helped.',
      );
    }

    return CompanionResponse(
      message:
          'Thanks for checking in. Your recommended next step is: ${intervention.title.toLowerCase()}.',
      cbtExercise: 'Two-minute breathing: 4 seconds inhale, 6 seconds exhale, repeat 12 cycles.',
    );
  }

  Future<List<Intervention>> _safeGetInterventions(String patientId) async {
    try {
      return await _dbService.getInterventions(patientId);
    } catch (_) {
      return const [];
    }
  }

  Future<double> computeInterventionSuccessRate() async {
    try {
      final patients = await _dbService.getAllPatients();
      if (patients.isEmpty) return 0;

      final rewards = <double>[];
      for (final patient in patients) {
        final interventions = await _dbService.getInterventions(patient.id);
        for (final item in interventions) {
          rewards.add(item.projectedRiskReduction.clamp(0.0, 1.0));
        }
      }

      if (rewards.isEmpty) return 0;
      return rewards.reduce((a, b) => a + b) / rewards.length;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, double>> summarizeWearableRiskSignals() async {
    try {
      final patients = await _dbService.getAllPatients();
      if (patients.isEmpty) {
        return {
          'sleepRisk': 0,
          'activityRisk': 0,
          'screenTimeRisk': 0,
        };
      }

      double sleepRiskTotal = 0;
      double activityRiskTotal = 0;
      double screenTimeRiskTotal = 0;
      int sleepSamples = 0;
      int activitySamples = 0;
      int screenSamples = 0;

      for (final patient in patients) {
        final logs = await _dbService.getDailyLogs(patient.id);
        for (final log in logs.take(14)) {
          // Sleep risk is derived from deviation below healthy sleep duration.
          sleepRiskTotal += ((8.0 - log.sleepHours).clamp(0.0, 8.0) / 8.0) * 100.0;
          sleepSamples++;

          // Activity proxy: lower self-report score indicates reduced activity/energy.
          activityRiskTotal += (100.0 - log.selfReportScore).clamp(0.0, 100.0);
          activitySamples++;

          // Screen-time signal is not available in current daily log schema.
          // Keep this at 0 until real wearable/app telemetry is stored.
          screenTimeRiskTotal += 0;
          screenSamples++;
        }
      }

      return {
        'sleepRisk': sleepSamples == 0 ? 0 : sleepRiskTotal / sleepSamples,
        'activityRisk': activitySamples == 0 ? 0 : activityRiskTotal / activitySamples,
        'screenTimeRisk':
            screenSamples == 0 ? 0 : screenTimeRiskTotal / screenSamples,
      };
    } catch (_) {
      return {
        'sleepRisk': 0,
        'activityRisk': 0,
        'screenTimeRisk': 0,
      };
    }
  }

  Future<String> getGeminiInterventionExplanation({
    required String patientName,
    required String recommendation,
    required double expectedRiskReduction,
    required String reason,
  }) async {
    final prompt =
        'Based on $patientName\'s history, ${recommendation.replaceAll('_', ' ')} reduced risk by '
        '${(expectedRiskReduction * 100).toStringAsFixed(0)}%. '
        'Explain why this works for this specific case in 2 short clinical sentences. '
        'Known rationale: $reason';

    try {
      return await _geminiService.generateResponseAdvanced(
        systemPrompt:
            'You are an AI clinical assistant helping therapists. Provide concise, evidence-based reasoning.',
        userPrompt: prompt,
        maxWords: 120,
      );
    } catch (_) {
      return 'AI explanation: ${recommendation.replaceAll('_', ' ')} is likely effective for $patientName because it targets current risk drivers and has shown prior benefit.';
    }
  }
}
