import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/appointment_v2.dart';

/// User-facing error raised by [AppointmentService]. [message] is safe to show.
class AppointmentException implements Exception {
  final String message;
  const AppointmentException(this.message);

  @override
  String toString() => message;
}

/// Raised when a slot overlaps another scheduled session of the therapist.
class AppointmentConflictException extends AppointmentException {
  const AppointmentConflictException(super.message);
}

/// Lightweight view of a patient linked to the current therapist.
class LinkedPatient {
  final String id;
  final String name;
  const LinkedPatient({required this.id, required this.name});
}

/// Single source of truth for sessions: Firestore `appointments/{id}`
/// (see docs/DATA_MODEL.md). Both apps listen with `.snapshots()`, so every
/// state change is visible on the other side in real time.
///
/// Client never writes `meetingUrl` (set by Cloud Function
/// `onAppointmentWritten`) and never sends push notifications (also the
/// function's job).
///
/// Queries used (rules must allow them):
///  * appointments where patientId == auth.uid
///  * appointments where therapistId == auth.uid
///  * appointments where therapistId == auth.uid && patientId == X
///  * appointments where therapistId == auth.uid && status == 'scheduled'
///  * appointments where patientId == auth.uid && status == 'requested'
///  * users where role == 'patient' && therapistId == auth.uid
///  * appointments/{id}/notes orderBy createdAt desc (therapist only)
class AppointmentService {
  AppointmentService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Patients may hold at most this many open (requested) sessions at once.
  static const int maxOpenRequests = 3;

  /// Minimum lead time for a new request / schedule.
  static const Duration minLeadTime = Duration(minutes: 5);

  /// Writes are queued offline by Firestore; stop blocking the UI after this.
  static const Duration writeTimeout = Duration(seconds: 20);

  CollectionReference<Map<String, dynamic>> get _appointments =>
      _db.collection('appointments');

  /// Human-readable message for any error thrown by this service or Firestore.
  static String describeError(Object error) {
    if (error is AppointmentException) return error.message;
    if (error is TimeoutException) {
      return 'No connection right now. The change is saved on this device and '
          'will be sent automatically when you are back online.';
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to do that.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'You appear to be offline. Please check your connection and try again.';
        case 'not-found':
          return 'This appointment no longer exists.';
        case 'failed-precondition':
          return 'The server could not complete this request. Please try again later.';
      }
      return 'Something went wrong (${error.code}). Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  String? get currentUid => _auth.currentUser?.uid;

  String _requireUid() {
    final uid = currentUid;
    if (uid == null) {
      throw const AppointmentException('You are signed out. Please sign in again.');
    }
    return uid;
  }

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  static List<AppointmentV2> _map(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(AppointmentV2.fromDoc).toList(growable: false);

  /// All appointments of [patientId] (the signed-in patient).
  Stream<List<AppointmentV2>> watchForPatient(String patientId) => _appointments
      .where('patientId', isEqualTo: patientId)
      .snapshots(includeMetadataChanges: true)
      .map(_map);

  /// All appointments of [therapistId], optionally only with [patientId].
  Stream<List<AppointmentV2>> watchForTherapist(
    String therapistId, {
    String? patientId,
  }) {
    Query<Map<String, dynamic>> q =
        _appointments.where('therapistId', isEqualTo: therapistId);
    if (patientId != null && patientId.isNotEmpty) {
      q = q.where('patientId', isEqualTo: patientId);
    }
    return q.snapshots(includeMetadataChanges: true).map(_map);
  }

  /// Live list of patients linked to [therapistId], sorted by name.
  Stream<List<LinkedPatient>> watchLinkedPatients(String therapistId) => _db
          .collection('users')
          .where('role', isEqualTo: 'patient')
          .where('therapistId', isEqualTo: therapistId)
          .snapshots()
          .map((snap) {
        final list = snap.docs.map((d) {
          final name = (d.data()['name'] ?? '').toString().trim();
          return LinkedPatient(id: d.id, name: name.isEmpty ? 'Unnamed patient' : name);
        }).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  /// Notes for one appointment, newest first (therapist only).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchNotes(String appointmentId) =>
      _appointments
          .doc(appointmentId)
          .collection('notes')
          .orderBy('createdAt', descending: true)
          .snapshots();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _userDoc(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data() ?? const <String, dynamic>{};
  }

  static String _clean(dynamic v) => (v ?? '').toString().trim();

  void _validateSlot(DateTime start, int durationMinutes) {
    if (!kAppointmentDurations.contains(durationMinutes)) {
      throw const AppointmentException('Choose a duration of 30, 45 or 60 minutes.');
    }
    if (start.isBefore(DateTime.now().add(minLeadTime))) {
      throw const AppointmentException(
          'That time is in the past or too soon. Please choose a later time.');
    }
  }

  /// Scheduled appointments of [therapistId] overlapping [start, start+minutes).
  /// [excludeId] ignores the appointment being accepted.
  Future<List<AppointmentV2>> findConflicts({
    required String therapistId,
    required DateTime start,
    required int durationMinutes,
    String? excludeId,
  }) async {
    final snap = await _appointments
        .where('therapistId', isEqualTo: therapistId)
        .where('status', isEqualTo: AppointmentStatus.scheduled)
        .get();
    return snap.docs
        .map(AppointmentV2.fromDoc)
        .where((a) => a.id != excludeId && a.overlaps(start, durationMinutes))
        .toList(growable: false);
  }

  Future<void> _ensureNoConflict({
    required String therapistId,
    required DateTime start,
    required int durationMinutes,
    String? excludeId,
  }) async {
    final conflicts = await findConflicts(
      therapistId: therapistId,
      start: start,
      durationMinutes: durationMinutes,
      excludeId: excludeId,
    );
    if (conflicts.isNotEmpty) {
      final c = conflicts.first;
      throw AppointmentConflictException(
        'Double booking: you already have a session with ${c.patientName} '
        'overlapping this time. Pick another slot.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Patient actions
  // ---------------------------------------------------------------------------

  /// Patient asks their linked therapist for a session (status `requested`).
  /// therapistId / therapistName come from the server-owned fields of
  /// `users/{uid}`; if absent the request is refused.
  Future<String> requestSession({
    required DateTime proposedAt,
    required int durationMinutes,
    required bool isVirtual,
    required String reason,
  }) async {
    final uid = _requireUid();
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AppointmentException('Please tell your therapist why you would like a session.');
    }
    _validateSlot(proposedAt, durationMinutes);

    final me = await _userDoc(uid);
    final therapistId = _clean(me['therapistId']);
    if (therapistId.isEmpty) {
      throw const AppointmentException(
        'You are not linked to a therapist yet. Join your therapist with their '
        'invite code first, then request a session.',
      );
    }

    final open = await _appointments
        .where('patientId', isEqualTo: uid)
        .where('status', isEqualTo: AppointmentStatus.requested)
        .get();
    if (open.size >= maxOpenRequests) {
      throw const AppointmentException(
        'You already have $maxOpenRequests pending requests. Please wait for '
        'your therapist to respond or cancel one.',
      );
    }

    final therapistName = _clean(me['therapistName']);
    final patientName = _clean(me['name']);
    final ref = _appointments.doc();
    await ref.set({
      'patientId': uid,
      'therapistId': therapistId,
      'patientName': patientName.isEmpty ? 'Patient' : patientName,
      'therapistName': therapistName.isEmpty ? 'Therapist' : therapistName,
      'requestedBy': 'patient',
      'status': AppointmentStatus.requested,
      'scheduledAt': null,
      'proposedAt': Timestamp.fromDate(proposedAt),
      'durationMinutes': durationMinutes,
      'isVirtual': isVirtual,
      'reason': trimmedReason,
      'notes': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(writeTimeout);
    return ref.id;
  }

  // ---------------------------------------------------------------------------
  // Therapist actions
  // ---------------------------------------------------------------------------

  /// Therapist books a session directly (status `scheduled`).
  Future<String> createScheduled({
    required String patientId,
    required String patientName,
    required DateTime scheduledAt,
    required int durationMinutes,
    required bool isVirtual,
    String reason = '',
    String notes = '',
  }) async {
    final uid = _requireUid();
    if (patientId.isEmpty) {
      throw const AppointmentException('Select a patient.');
    }
    _validateSlot(scheduledAt, durationMinutes);
    await _ensureNoConflict(
      therapistId: uid,
      start: scheduledAt,
      durationMinutes: durationMinutes,
    );

    final me = await _userDoc(uid);
    final therapistName = _clean(me['name']);
    final ref = _appointments.doc();
    await ref.set({
      'patientId': patientId,
      'therapistId': uid,
      'patientName': patientName.trim().isEmpty ? 'Patient' : patientName.trim(),
      'therapistName': therapistName.isEmpty ? 'Therapist' : therapistName,
      'requestedBy': 'therapist',
      'status': AppointmentStatus.scheduled,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'proposedAt': null,
      'durationMinutes': durationMinutes,
      'isVirtual': isVirtual,
      'reason': reason.trim(),
      'notes': notes.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(writeTimeout);
    return ref.id;
  }

  /// Runs [apply] inside a transaction after verifying the current status is
  /// one of [allowedFrom] (guards against the other side changing it).
  Future<void> _transition(
    String appointmentId, {
    required List<String> allowedFrom,
    required Map<String, dynamic> Function(Map<String, dynamic> current) apply,
  }) async {
    final ref = _appointments.doc(appointmentId);
    // Return an error message instead of throwing inside the handler so the
    // message is never wrapped by the platform channel.
    final error = await _db.runTransaction<String?>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (!snap.exists || data == null) {
        return 'This appointment no longer exists.';
      }
      final status = _clean(data['status']);
      if (!allowedFrom.contains(status)) {
        return 'This appointment is already '
            '${AppointmentStatus.label(status).toLowerCase()}.';
      }
      tx.update(ref, {
        ...apply(data),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    });
    if (error != null) throw AppointmentException(error);
  }

  /// Therapist accepts a request at [scheduledAt] (status `scheduled`).
  Future<void> accept(AppointmentV2 appt, DateTime scheduledAt) async {
    final uid = _requireUid();
    if (appt.therapistId != uid) {
      throw const AppointmentException('Only the assigned therapist can accept this request.');
    }
    _validateSlot(scheduledAt, appt.durationMinutes);
    await _ensureNoConflict(
      therapistId: uid,
      start: scheduledAt,
      durationMinutes: appt.durationMinutes,
      excludeId: appt.id,
    );
    await _transition(
      appt.id,
      allowedFrom: const [AppointmentStatus.requested],
      apply: (_) => {
        'status': AppointmentStatus.scheduled,
        'scheduledAt': Timestamp.fromDate(scheduledAt),
      },
    );
  }

  static String _appendNote(dynamic existing, String line) {
    final prev = _clean(existing);
    return prev.isEmpty ? line : '$prev\n$line';
  }

  /// Therapist declines a request. The reason is appended to `notes`.
  Future<void> decline(AppointmentV2 appt, String reason) async {
    _requireUid();
    final r = reason.trim();
    await _transition(
      appt.id,
      allowedFrom: const [AppointmentStatus.requested],
      apply: (cur) => {
        'status': AppointmentStatus.declined,
        if (r.isNotEmpty) 'notes': _appendNote(cur['notes'], 'Declined: $r'),
      },
    );
  }

  /// Either party cancels. [byRole] is 'patient' or 'therapist'.
  Future<void> cancel(AppointmentV2 appt, {required String byRole, String reason = ''}) async {
    _requireUid();
    final r = reason.trim();
    await _transition(
      appt.id,
      allowedFrom: const [AppointmentStatus.requested, AppointmentStatus.scheduled],
      apply: (cur) => {
        'status': AppointmentStatus.cancelled,
        'cancelledBy': byRole,
        if (r.isNotEmpty)
          'notes': _appendNote(cur['notes'], 'Cancelled by $byRole: $r'),
      },
    );
  }

  /// Therapist records the outcome of a session that has started.
  Future<void> markOutcome(AppointmentV2 appt, String outcome) async {
    _requireUid();
    if (outcome != AppointmentStatus.completed && outcome != AppointmentStatus.noShow) {
      throw const AppointmentException('Invalid outcome.');
    }
    if (!appt.hasStarted(DateTime.now())) {
      throw const AppointmentException('You can record the outcome once the session has started.');
    }
    await _transition(
      appt.id,
      allowedFrom: const [AppointmentStatus.scheduled],
      apply: (_) => {'status': outcome},
    );
  }

  /// Therapist adds a private session note (immutable once written).
  Future<void> addNote(String appointmentId, String text) async {
    final uid = _requireUid();
    final t = text.trim();
    if (t.isEmpty) throw const AppointmentException('Note is empty.');
    await _appointments.doc(appointmentId).collection('notes').add({
      'therapistId': uid,
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(writeTimeout);
  }
}
