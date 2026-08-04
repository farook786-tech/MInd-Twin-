import 'database_service.dart';

class SentimentResult {
  final String sentiment;
  final String emotion;
  final double score;
  final double confidence;
  final List<String> clinicalFlags;
  final List<String> crisisKeywords;

  const SentimentResult({
    required this.sentiment,
    required this.emotion,
    required this.score,
    required this.confidence,
    required this.clinicalFlags,
    required this.crisisKeywords,
  });
}

class CrisisDetectionResult {
  final bool crisisDetected;
  final String severity;
  final String triggerLayer;
  final List<String> matchedPhrases;
  final double confidence;
  final String recommendedAction;
  final String safetyPlan;

  const CrisisDetectionResult({
    required this.crisisDetected,
    required this.severity,
    required this.triggerLayer,
    required this.matchedPhrases,
    required this.confidence,
    required this.recommendedAction,
    required this.safetyPlan,
  });
}

class MlSentimentService {
  final DatabaseService _databaseService = DatabaseService();

  Future<SentimentResult> analyzeSentiment(String text) async {
    final normalized = text.toLowerCase();
    final matches = _matchedTerms(normalized);

    double score = 0.0;
    if (matches.contains('hope')) score += 0.35;
    if (matches.contains('calm')) score += 0.25;
    if (matches.contains('good')) score += 0.20;
    if (matches.contains('happy')) score += 0.30;
    if (matches.contains('sad')) score -= 0.35;
    if (matches.contains('anxious')) score -= 0.30;
    if (matches.contains('hopeless')) score -= 0.45;
    if (matches.contains('self-harm')) score -= 0.75;

    score = score.clamp(-1.0, 1.0);
    final sentiment = score > 0.15
        ? 'positive'
        : score < -0.15
            ? 'negative'
            : 'neutral';

    final emotion = matches.contains('anxious')
        ? 'anxious'
        : matches.contains('sad')
            ? 'sad'
            : matches.contains('angry')
                ? 'angry'
                : matches.contains('hope')
                    ? 'hopeful'
                    : 'neutral';

    final flags = <String>[];
    if (matches.contains('hopeless')) flags.add('hopelessness');
    if (matches.contains('self-harm')) flags.add('self_harm_language');
    if (matches.contains('sleep')) flags.add('sleep_related_distress');
    if (matches.contains('anxious')) flags.add('anxiety_language');

    return SentimentResult(
      sentiment: sentiment,
      emotion: emotion,
      score: score,
      confidence: matches.isEmpty ? 0.55 : 0.75,
      clinicalFlags: flags,
      crisisKeywords: matches,
    );
  }

  Future<CrisisDetectionResult> detectCrisis(
    String messageText,
    String patientId,
    List<String> recentHistory,
  ) async {
    final currentTerms = _matchedTerms(messageText.toLowerCase());
    final recentTerms = recentHistory.expand((entry) => _matchedTerms(entry.toLowerCase())).toSet().toList();

    double confidence = currentTerms.isEmpty && recentTerms.isEmpty ? 0.0 : 0.55 + ((currentTerms.length + recentTerms.length) * 0.06);
    confidence = confidence.clamp(0.0, 0.98);

    final hasCriticalPhrase = [...currentTerms, ...recentTerms].any((term) => const [
      'self-harm',
      'suicide',
      'kill myself',
      'end my life',
      'hurt myself',
    ].contains(term));

    final crisisDetected = hasCriticalPhrase || confidence >= 0.65;
    final severity = hasCriticalPhrase
        ? 'critical'
        : confidence >= 0.8
            ? 'high'
            : confidence >= 0.65
                ? 'moderate'
                : 'low';

    return CrisisDetectionResult(
      crisisDetected: crisisDetected,
      severity: severity,
      triggerLayer: currentTerms.isNotEmpty ? 'message' : 'history',
      matchedPhrases: [...currentTerms, ...recentTerms].toSet().toList(),
      confidence: confidence,
      recommendedAction: hasCriticalPhrase
          ? 'Open safety resources and contact support immediately.'
          : 'Offer grounding and encourage therapist follow-up.',
      safetyPlan: hasCriticalPhrase
          ? 'Move to a safe place, call local emergency services, and contact a trusted person.'
          : 'Pause, breathe slowly, and use coping steps before deciding on next action.',
    );
  }

  List<String> _matchedTerms(String text) {
    final terms = <String>[];

    void addIfMatches(String token, List<String> patterns) {
      if (patterns.any(text.contains)) {
        terms.add(token);
      }
    }

    addIfMatches('hope', ['hope', 'better soon', 'improving']);
    addIfMatches('calm', ['calm', 'grounded', 'relaxed']);
    addIfMatches('good', ['good', 'okay', 'fine', 'better']);
    addIfMatches('happy', ['happy', 'glad', 'grateful']);
    addIfMatches('sad', ['sad', 'down', 'cry', 'depressed']);
    addIfMatches('anxious', ['anxious', 'panic', 'worried', 'nervous']);
    addIfMatches('angry', ['angry', 'furious', 'mad', 'frustrated']);
    addIfMatches('hopeless', ['hopeless', 'nothing matters', 'can not do this']);
    addIfMatches('self-harm', ['self-harm', 'suicide', 'kill myself', 'hurt myself', 'end my life']);
    addIfMatches('sleep', ['sleep', 'insomnia', 'nightmare', 'barely slept']);

    return terms.toSet().toList();
  }
}