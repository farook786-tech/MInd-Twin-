import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/daily_log.dart';

/// Reads a patient's daily check-in history from Firestore (the real
/// source of truth for the app) and maps the documents onto [DailyLog]
/// models consumed by the ML analysis services.
class DailyLogSource {
  static final DailyLogSource _instance = DailyLogSource._internal();

  factory DailyLogSource() => _instance;

  DailyLogSource._internal();

  /// Scoped daily_logs query for [patientId], newest first.
  ///
  /// Security rules are not filters: when the signed-in user is NOT the
  /// patient (i.e. a therapist), the query must also constrain
  /// `therapistId == myUid` so it only asks for documents the rules allow.
  static Query<Map<String, dynamic>> scopedQuery(String patientId) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('daily_logs')
        .where('patientId', isEqualTo: patientId);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null && myUid != patientId) {
      query = query.where('therapistId', isEqualTo: myUid);
    }
    return query.orderBy('timestamp', descending: true);
  }

  /// Newest-first list of the patient's logged days.
  /// Returns an empty list on any query error (logged).
  Future<List<DailyLog>> getDailyLogs(String patientId, {int limit = 60}) async {
    try {
      final snapshot = await scopedQuery(patientId).limit(limit).get();

      final logs = snapshot.docs
          .map((doc) => _fromDocument(doc.id, doc.data()))
          .toList();
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return logs;
    } catch (error) {
      debugPrint('DailyLogSource.getDailyLogs($patientId) failed: $error');
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
                ? (DateTime.tryParse(ts) ?? DateTime.fromMillisecondsSinceEpoch(0))
                // Pending server timestamp (local write not yet acked) -> now.
                : DateTime.now();

    // Map the check-in CHOICE KEYS (not the ordinal score, whose order is
    // not clinical severity: 'sad' has score 3 but is the worst mood) onto
    // the higher-is-better scales the ML services expect. Unknown / missing
    // values stay null - never a fabricated neutral default.
    final moodKey = data['moodKey']?.toString();
    final sleepKey = data['sleepKey']?.toString();
    final energyKey = data['energyKey']?.toString();

    return DailyLog(
      id: id,
      patientId: data['patientId'] ?? '',
      timestamp: timestamp,
      moodScore: moodKey == null ? null : moodByKey[moodKey],
      sleepHours: sleepKey == null ? null : sleepHoursByKey[sleepKey],
      energyLevel: energyKey == null ? null : energyByKey[energyKey],
      anxietyLevel: _num(data['anxietyLevel']),
      selfReportScore: _num(data['selfReportScore']),
      wellbeingScore: _num(data['wellbeingScore']),
      date: _dateString(timestamp),
      notes: (data['optionalNote'] ?? data['summaryText'])?.toString(),
    );
  }

  /// Mood choice -> 0..10 (10 = best). Mirrors MlRiskService.checkInMoodRisk.
  static const Map<String, double> moodByKey = {
    'great': 10.0,
    'okay': 6.7,
    'frustrated': 3.3,
    'anxious': 1.5,
    'sad': 0.0,
  };

  /// Sleep choice -> representative hours (labels: great 7-9 h, okay 5-7 h,
  /// poor 3-5 h, barely < 3 h, too_much 10+ h).
  static const Map<String, double> sleepHoursByKey = {
    'great': 8.0,
    'okay': 6.0,
    'poor': 4.0,
    'barely_slept': 2.0,
    'too_much': 11.0,
  };

  /// Energy choice -> 0..10 (10 = best).
  static const Map<String, double> energyByKey = {
    'high': 10.0,
    'normal': 10.0,
    'low': 4.0,
    'drained': 0.0,
  };

  static double? _num(dynamic v) => (v is num && v.isFinite) ? v.toDouble() : null;

  String _dateString(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
