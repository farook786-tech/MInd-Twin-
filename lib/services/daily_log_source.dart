import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_log.dart';

/// Reads a patient's daily check-in history from Firestore (the real
/// source of truth for the app) and maps the documents onto [DailyLog]
/// models consumed by the ML analysis services.
class DailyLogSource {
  static final DailyLogSource _instance = DailyLogSource._internal();

  factory DailyLogSource() => _instance;

  DailyLogSource._internal();

  /// Newest-first list of the patient's logged days.
  /// Returns an empty list on any query error.
  Future<List<DailyLog>> getDailyLogs(String patientId, {int limit = 60}) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('daily_logs')
          .where('patientId', isEqualTo: patientId)
          .limit(limit)
          .get();

      final logs = snapshot.docs
          .map((doc) => _fromDocument(doc.id, doc.data()))
          .toList();
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return logs;
    } catch (_) {
      return const [];
    }
  }

  DailyLog _fromDocument(String id, Map<String, dynamic> data) {
    final ts = data['timestamp'];
    final DateTime timestamp = ts is Timestamp
        ? ts.toDate()
        : ts is DateTime
            ? ts
            : ts is String
                ? (DateTime.tryParse(ts) ?? DateTime.now())
                : DateTime.now();

    // Firestore stores the check-in choices on an inverted scale where a
    // lower score is better (mood: 1=great..5=frustrated, energy & sleep:
    // 1=best..4=worst). The ML services expect DailyLog on a higher-is-better
    // scale (mood/energy 0-10, sleep in hours 0-12), so normalize here.
    final double moodScore = _invertToBestScale(
      (data['moodScore'] ?? 3).toDouble(),
      min: 1,
      max: 5,
    ) * 10; // -> 0-10, 10 = best

    final double sleepHours = _sleepScoreToHours(
      (data['sleepScore'] ?? 2).toDouble(),
    ); // -> 0-12 hours, higher = better

    final double energyLevel = _invertToBestScale(
      (data['energyScore'] ?? 2).toDouble(),
      min: 1,
      max: 4,
    ) * 10; // -> 0-10, 10 = best

    return DailyLog(
      id: id,
      patientId: data['patientId'] ?? '',
      timestamp: timestamp,
      moodScore: moodScore,
      sleepHours: sleepHours,
      energyLevel: energyLevel,
      anxietyLevel: (data['anxietyLevel'] ?? 5.0).toDouble(),
      selfReportScore:
          (data['selfReportScore'] ?? data['wellbeingScore'] ?? 50).toDouble(),
      wellbeingScore: (data['wellbeingScore'] ?? 50).toDouble(),
      date: _dateString(timestamp),
      notes: (data['optionalNote'] ?? data['summaryText'])?.toString(),
    );
  }

  /// Map a 1..[max] score where [min] is best onto a 0..1 scale where 1 is best.
  double _invertToBestScale(double score, {required double min, required double max}) {
    final clamped = score.clamp(min, max);
    return ((max - clamped) / (max - min)).toDouble();
  }

  /// Map the 1..4 sleep choice (1=best, 4=worst) onto estimated hours slept,
  /// matching the option labels (great 7-9h, okay 5-7h, poor 3-5h, barely <3h).
  double _sleepScoreToHours(double score) {
    final clamped = score.clamp(1, 4);
    return (8.0 - (clamped - 1) * 2.0);
  }

  String _dateString(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
