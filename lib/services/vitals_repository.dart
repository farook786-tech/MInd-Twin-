import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Vital types / units / sources exactly as in docs/DATA_MODEL.md (`vitals`).
enum VitalType { heartRate, sleep, steps }

extension VitalTypeX on VitalType {
  String get id => switch (this) {
        VitalType.heartRate => 'heart_rate',
        VitalType.sleep => 'sleep',
        VitalType.steps => 'steps',
      };

  String get unit => switch (this) {
        VitalType.heartRate => 'bpm',
        VitalType.sleep => 'hours',
        VitalType.steps => 'count',
      };

  /// Key used in `users/{uid}.latestVitals`.
  String get latestKey => switch (this) {
        VitalType.heartRate => 'heartRate',
        VitalType.sleep => 'sleepHours',
        VitalType.steps => 'steps',
      };

  static VitalType? fromId(String? id) => switch (id) {
        'heart_rate' => VitalType.heartRate,
        'sleep' => VitalType.sleep,
        'steps' => VitalType.steps,
        _ => null,
      };
}

/// One real measurement. [measuredAt] is the real reading time (stored as UTC Timestamp).
class VitalReading {
  final VitalType type;
  final double value;
  final DateTime measuredAt;
  final String source; // 'wear_os' | 'health_connect'

  const VitalReading({
    required this.type,
    required this.value,
    required this.measuredAt,
    required this.source,
  });

  String docId(String patientId) =>
      '${patientId}_${type.id}_${measuredAt.toUtc().millisecondsSinceEpoch}';

  factory VitalReading.fromDoc(Map<String, dynamic> d) {
    final ts = d['measuredAt'];
    return VitalReading(
      type: VitalTypeX.fromId(d['type'] as String?) ?? VitalType.heartRate,
      value: (d['value'] as num?)?.toDouble() ?? double.nan,
      measuredAt: ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      source: (d['source'] as String?) ?? 'unknown',
    );
  }
}

/// Writes and reads the Firestore `vitals` collection (single source of truth).
class VitalsRepository {
  VitalsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _writeTimeout = Duration(seconds: 20);

  CollectionReference<Map<String, dynamic>> get _vitals => _db.collection('vitals');

  /// Writes [readings] for [patientId] with deterministic ids (dedupe) and updates
  /// `users/{patientId}.latestVitals` for the newest reading of each type.
  ///
  /// Returns false if any write failed with an error other than offline queueing or
  /// PERMISSION_DENIED on an already-existing (immutable) doc, so the caller can keep its
  /// watermark and retry.
  Future<bool> writeReadings({
    required String patientId,
    required String? therapistId,
    required List<VitalReading> readings,
  }) async {
    if (readings.isEmpty) return true;
    var ok = true;
    final newest = <VitalType, VitalReading>{};

    const chunk = 50;
    for (var i = 0; i < readings.length; i += chunk) {
      final part = readings.sublist(i, (i + chunk).clamp(0, readings.length));
      final results = await Future.wait(part.map((r) async {
        if (!r.value.isFinite) return true;
        final data = <String, dynamic>{
          'patientId': patientId,
          'therapistId': therapistId,
          'type': r.type.id,
          'value': r.value,
          'unit': r.type.unit,
          'measuredAt': Timestamp.fromDate(r.measuredAt.toUtc()),
          'source': r.source,
          'createdAt': FieldValue.serverTimestamp(),
        };
        try {
          await _vitals.doc(r.docId(patientId)).set(data).timeout(_writeTimeout);
        } on TimeoutException {
          // Offline: the write is in Firestore's persisted queue and will be sent later.
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') {
            debugPrint('[VitalsRepository] write failed (${e.code}) for ${r.docId(patientId)}');
            return false;
          }
          // Immutable doc already exists (or rules reject): retrying cannot help.
          debugPrint('[VitalsRepository] permission-denied for ${r.docId(patientId)}');
        }
        final prev = newest[r.type];
        if (prev == null || r.measuredAt.isAfter(prev.measuredAt)) newest[r.type] = r;
        return true;
      }));
      if (results.contains(false)) ok = false;
    }

    if (newest.isNotEmpty) {
      final latest = <String, dynamic>{
        for (final r in newest.values)
          r.type.latestKey: {
            'value': r.value,
            'measuredAt': Timestamp.fromDate(r.measuredAt.toUtc()),
          },
      };
      // Fire-and-forget: never block sync on the snapshot field.
      unawaited(_db
          .collection('users')
          .doc(patientId)
          .set({'latestVitals': latest}, SetOptions(merge: true))
          .catchError((Object e) => debugPrint('[VitalsRepository] latestVitals: $e')));
    }
    return ok;
  }

  /// Live stream of a patient's vitals since [since], newest first.
  /// Requires composite index: vitals (patientId ASC, measuredAt DESC).
  Stream<List<VitalReading>> watchSince(String patientId, DateTime since, {int limit = 2000}) {
    return _vitals
        .where('patientId', isEqualTo: patientId)
        .where('measuredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since.toUtc()))
        .orderBy('measuredAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => VitalReading.fromDoc(d.data())).toList());
  }
}
