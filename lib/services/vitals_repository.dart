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

/// One real measurement, or one 5-minute heart-rate window (docs/DATA_MODEL.md).
/// [measuredAt] is the real reading time (window END for a window), stored as UTC Timestamp.
class VitalReading {
  final VitalType type;
  final double value;
  final DateTime measuredAt;
  final String source; // 'wear_os' | 'health_connect'

  /// 5-minute heart-rate window fields (null for single readings).
  final DateTime? windowStart;
  final double? min;
  final double? max;
  final int? sampleCount;

  /// True for an out-of-range heart-rate sample written immediately (not aggregated)
  /// so the server threshold check is not delayed by the window.
  final bool immediate;

  const VitalReading({
    required this.type,
    required this.value,
    required this.measuredAt,
    required this.source,
    this.windowStart,
    this.min,
    this.max,
    this.sampleCount,
    this.immediate = false,
  });

  bool get isWindow => windowStart != null;

  /// Deterministic ids (dedupe; vitals docs are immutable):
  /// window `${uid}_heart_rate_${windowStartMillis}`,
  /// immediate `${uid}_heart_rate_imm_${measuredAtMillis}`,
  /// other `${uid}_${type}_${measuredAtMillis}`.
  String docId(String patientId) {
    if (windowStart != null) {
      return '${patientId}_${type.id}_${windowStart!.toUtc().millisecondsSinceEpoch}';
    }
    if (immediate) return '${patientId}_${type.id}_imm_${measuredAt.toUtc().millisecondsSinceEpoch}';
    return '${patientId}_${type.id}_${measuredAt.toUtc().millisecondsSinceEpoch}';
  }

  factory VitalReading.fromDoc(Map<String, dynamic> d) {
    final ts = d['measuredAt'];
    final ws = d['windowStart'];
    double? n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    return VitalReading(
      type: VitalTypeX.fromId(d['type'] as String?) ?? VitalType.heartRate,
      value: (d['value'] as num?)?.toDouble() ?? double.nan,
      measuredAt: ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      source: (d['source'] as String?) ?? 'unknown',
      windowStart: ws is Timestamp ? ws.toDate() : null,
      min: n(d['min']),
      max: n(d['max']),
      sampleCount: (d['sampleCount'] is num) ? (d['sampleCount'] as num).toInt() : null,
      immediate: d['immediate'] == true,
    );
  }

  /// Firestore fields (without patientId / therapistId / createdAt).
  Map<String, dynamic> toFields() => {
        'type': type.id,
        'value': value,
        'unit': type.unit,
        'measuredAt': Timestamp.fromDate(measuredAt.toUtc()),
        'source': source,
        if (windowStart != null) ...{
          'windowStart': Timestamp.fromDate(windowStart!.toUtc()),
          'min': min,
          'max': max,
          'sampleCount': sampleCount,
        },
        if (immediate) 'immediate': true,
      };
}

/// Writes and reads the Firestore `vitals` collection (single source of truth).
class VitalsRepository {
  VitalsRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _writeTimeout = Duration(seconds: 20);

  CollectionReference<Map<String, dynamic>> get _vitals => _db.collection('vitals');

  /// Writes [readings] for [patientId] with deterministic ids (dedupe). Does NOT touch
  /// `users.latestVitals` (see [updateLatestVitals]; throttled by the caller because every
  /// users-doc write is also a read for each therapist screen listening to it).
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

    const chunk = 50;
    for (var i = 0; i < readings.length; i += chunk) {
      final part = readings.sublist(i, (i + chunk).clamp(0, readings.length));
      final results = await Future.wait(part.map((r) async {
        if (!r.value.isFinite) return true;
        final data = <String, dynamic>{
          'patientId': patientId,
          'therapistId': therapistId,
          ...r.toFields(),
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
        return true;
      }));
      if (results.contains(false)) ok = false;
    }
    return ok;
  }

  /// Merges the newest reading of each type into `users/{patientId}.latestVitals`.
  /// Fire-and-forget: never blocks sync on the snapshot field.
  void updateLatestVitals(String patientId, Iterable<VitalReading> readings) {
    final newest = <VitalType, VitalReading>{};
    for (final r in readings) {
      if (!r.value.isFinite) continue;
      final prev = newest[r.type];
      if (prev == null || r.measuredAt.isAfter(prev.measuredAt)) newest[r.type] = r;
    }
    if (newest.isEmpty) return;
    final latest = <String, dynamic>{
      for (final r in newest.values)
        r.type.latestKey: {
          'value': r.type == VitalType.heartRate ? r.value.roundToDouble() : r.value,
          'measuredAt': Timestamp.fromDate(r.measuredAt.toUtc()),
        },
    };
    unawaited(_db.collection('users').doc(patientId).set({'latestVitals': latest},
        SetOptions(merge: true)).catchError((Object e) => debugPrint('[VitalsRepository] latestVitals: $e')));
  }

  /// Merges fields into `vitals_daily/{patientId}_{dateKey}` (docs/DATA_MODEL.md).
  /// [fields] may contain only the summary keys allowed by firestore.rules
  /// (hrRestingEstimate, hrAvg, hrMin, hrMax, hrWindows, sleepHours, steps).
  /// Returns false on a non-offline failure so the caller can retry later.
  Future<bool> mergeDaily({
    required String patientId,
    required String? therapistId,
    required String dateKey,
    required Map<String, Object?> fields,
  }) async {
    if (fields.isEmpty) return true;
    final data = <String, dynamic>{
      'patientId': patientId,
      'therapistId': therapistId,
      'date': dateKey,
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await _db
          .collection('vitals_daily')
          .doc('${patientId}_$dateKey')
          .set(data, SetOptions(merge: true))
          .timeout(_writeTimeout);
      return true;
    } on TimeoutException {
      return true; // queued offline
    } on FirebaseException catch (e) {
      debugPrint('[VitalsRepository] vitals_daily $dateKey failed (${e.code})');
      return false;
    }
  }

  /// Live stream of a patient's vitals since [since], newest first.
  /// Requires composite index: vitals (patientId ASC, measuredAt DESC).
  /// With 5-minute heart-rate windows a 24 h range is <= 288 window docs plus the
  /// rare immediate / sleep docs, so [limit] bounds the reads per open.
  Stream<List<VitalReading>> watchSince(String patientId, DateTime since, {int limit = 320}) {
    return _vitals
        .where('patientId', isEqualTo: patientId)
        .where('measuredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since.toUtc()))
        .orderBy('measuredAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => VitalReading.fromDoc(d.data())).toList());
  }
}
