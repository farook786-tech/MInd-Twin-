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

    return DailyLog(
      id: id,
      patientId: data['patientId'] ?? '',
      timestamp: timestamp,
      moodScore: (data['moodScore'] ?? 5).toDouble(),
      sleepHours: (data['sleepScore'] ?? 7).toDouble(),
      energyLevel: (data['energyScore'] ?? 5).toDouble(),
      anxietyLevel: (data['anxietyLevel'] ?? 5.0).toDouble(),
      selfReportScore:
          (data['selfReportScore'] ?? data['wellbeingScore'] ?? 50).toDouble(),
      wellbeingScore: (data['wellbeingScore'] ?? 50).toDouble(),
      date: _dateString(timestamp),
      notes: (data['optionalNote'] ?? data['summaryText'])?.toString(),
    );
  }

  String _dateString(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
