import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Result of a patient-initiated crisis report.
enum CrisisReportStatus {
  /// Server acknowledged the write; the therapist push is being sent.
  delivered,

  /// Written to Firestore's offline queue; it will be delivered
  /// automatically when the device reconnects.
  queued,

  /// The patient has no linked therapist: the event is recorded, but no
  /// clinician will be notified. UI MUST direct the user to emergency help.
  noTherapist,

  /// Could not be written at all (e.g. signed out / rules rejected).
  failed,
}

/// Writes PATIENT-INITIATED crisis events (`sos`, `checkin_crisis`,
/// `chat_crisis`, and `phq9_severe` for PHQ-9 item 9 > 0 with a
/// deterministic id shared with the Cloud Function) in the exact `crisis_events` contract shape
/// (docs/DATA_MODEL.md). Automatic, score-based crisis events (risk >= 75,
/// PHQ-9 >= 20, item 9 > 0, vitals) are created ONLY by Cloud Functions to
/// avoid duplicates.
///
/// Never blocks the caller on the network for more than a few seconds, so
/// the safety-resources screen opens immediately even when offline.
class PatientCrisisReporter {
  PatientCrisisReporter._();

  static const Set<String> _patientEventTypes = {'sos', 'checkin_crisis', 'chat_crisis', 'phq9_severe'};

  static Future<CrisisReportStatus> report({
    required String eventType,
    required String severity,
    required String title,
    required String message,
    String? source,
    Map<String, dynamic>? details,
    String? docId,
  }) async {
    assert(_patientEventTypes.contains(eventType), 'Patients may only create $_patientEventTypes');
    assert(const {'critical', 'high', 'medium'}.contains(severity));

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return CrisisReportStatus.failed;

    final auth = AuthService();
    final therapistId = await auth.loadTherapistId();
    final cachedName = auth.getCurrentUser()?['name']?.toString().trim();
    final patientName = (cachedName != null && cachedName.isNotEmpty)
        ? cachedName
        : (user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : 'Patient');

    final col = FirebaseFirestore.instance.collection('crisis_events');
    final ref = docId == null ? col.doc() : col.doc(docId);
    final data = <String, dynamic>{
      'patientId': user.uid,
      'therapistId': therapistId,
      'patientName': patientName,
      'eventType': eventType,
      'severity': severity,
      'title': title,
      'message': message,
      'acknowledged': false,
      'timestamp': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.now(),
      if (source != null) 'source': source,
      if (details != null && details.isNotEmpty) 'details': details,
    };

    // set() resolves only after the server ack; the write is already in the
    // local queue the moment set() is called.
    final write = ref.set(data);
    try {
      await write.timeout(const Duration(seconds: 6));
      return therapistId == null ? CrisisReportStatus.noTherapist : CrisisReportStatus.delivered;
    } on TimeoutException {
      write.catchError((Object e) => debugPrint('[Crisis] queued write failed later: $e'));
      return therapistId == null ? CrisisReportStatus.noTherapist : CrisisReportStatus.queued;
    } catch (e) {
      debugPrint('[Crisis] crisis_events write failed: $e');
      return CrisisReportStatus.failed;
    }
  }

  /// User-facing explanation of [status].
  static String describe(CrisisReportStatus status) {
    switch (status) {
      case CrisisReportStatus.delivered:
        return 'Your therapist has been alerted.';
      case CrisisReportStatus.queued:
        return 'You appear to be offline. Your alert will be sent to your therapist as soon as you reconnect. '
            'If you are in danger, call your local emergency number now.';
      case CrisisReportStatus.noTherapist:
        return 'You are not linked to a therapist, so no clinician was alerted. '
            'If you are in danger, call your local emergency number now.';
      case CrisisReportStatus.failed:
        return 'We could not alert your therapist. If you are in danger, call your local emergency number now.';
    }
  }
}
