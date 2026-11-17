import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/safety_plan.dart';
import 'auth_service.dart';

/// Result of saving a safety plan.
enum SafetyPlanSaveStatus {
  /// The server acknowledged the write.
  saved,

  /// Kept on this device (Firestore offline queue); syncs when back online.
  savedOffline,

  /// Rejected (signed out, permission denied, invalid data).
  failed,
}

/// Reads / writes `safety_plans/{patientId}` (docs/DATA_MODEL.md).
///
/// Offline-first: Firestore's persistent cache serves reads and queues writes,
/// so the plan is available in a crisis without a network connection.
class SafetyPlanService {
  SafetyPlanService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String collection = 'safety_plans';

  DocumentReference<Map<String, dynamic>> _ref(String patientId) =>
      _db.collection(collection).doc(patientId);

  /// Live plan (cache first, then server). Emits an empty plan when none exists.
  Stream<SafetyPlan> watch(String patientId) => _ref(patientId)
      .snapshots(includeMetadataChanges: false)
      .map((s) => SafetyPlan.fromMap(patientId, s.data()));

  /// One-shot read that never waits long on the network: device cache first,
  /// then the server with a short timeout. Returns null if nothing is known.
  Future<SafetyPlan?> loadFast(String patientId, {Duration serverTimeout = const Duration(seconds: 3)}) async {
    try {
      final cached = await _ref(patientId).get(const GetOptions(source: Source.cache));
      if (cached.exists) return SafetyPlan.fromMap(patientId, cached.data());
    } catch (_) {
      // Not in cache.
    }
    try {
      final snap = await _ref(patientId).get().timeout(serverTimeout);
      return snap.exists ? SafetyPlan.fromMap(patientId, snap.data()) : null;
    } catch (e) {
      debugPrint('[SafetyPlan] load failed: $e');
      return null;
    }
  }

  /// Saves [plan]. The patient writes the whole document (stamped with their
  /// current therapistId); the patient's current therapist merges ONLY the
  /// plan content fields (+ their own therapistId stamp, so a plan drafted in
  /// session can be created before the patient opens it).
  Future<SafetyPlanSaveStatus> save(SafetyPlan plan, {required bool asTherapist}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return SafetyPlanSaveStatus.failed;

    final Future<void> write;
    if (asTherapist) {
      write = _ref(plan.patientId).set({
        'patientId': plan.patientId,
        'therapistId': user.uid,
        ...plan.contentFields(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      }, SetOptions(merge: true));
    } else {
      if (user.uid != plan.patientId) return SafetyPlanSaveStatus.failed;
      final therapistId = await AuthService().loadTherapistId();
      write = _ref(plan.patientId).set({
        'patientId': plan.patientId,
        'therapistId': therapistId,
        ...plan.contentFields(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });
    }

    try {
      await write.timeout(const Duration(seconds: 5));
      return SafetyPlanSaveStatus.saved;
    } on TimeoutException {
      // Already in the local queue; delivered automatically when online.
      write.catchError((Object e) => debugPrint('[SafetyPlan] queued save failed later: $e'));
      return SafetyPlanSaveStatus.savedOffline;
    } catch (e) {
      debugPrint('[SafetyPlan] save failed: $e');
      return SafetyPlanSaveStatus.failed;
    }
  }
}
