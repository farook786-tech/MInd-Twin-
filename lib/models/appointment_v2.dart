import 'package:cloud_firestore/cloud_firestore.dart';

/// Appointment statuses exactly as defined in docs/DATA_MODEL.md.
class AppointmentStatus {
  AppointmentStatus._();

  static const String requested = 'requested';
  static const String scheduled = 'scheduled';
  static const String declined = 'declined';
  static const String cancelled = 'cancelled';
  static const String completed = 'completed';
  static const String noShow = 'no_show';

  static const List<String> all = [
    requested,
    scheduled,
    declined,
    cancelled,
    completed,
    noShow,
  ];

  static String label(String status) {
    switch (status) {
      case requested:
        return 'Requested';
      case scheduled:
        return 'Scheduled';
      case declined:
        return 'Declined';
      case cancelled:
        return 'Cancelled';
      case completed:
        return 'Completed';
      case noShow:
        return 'No-show';
      default:
        return 'Unknown';
    }
  }
}

/// Allowed session lengths (minutes) per the data contract.
const List<int> kAppointmentDurations = [30, 45, 60];

/// How early before `scheduledAt` the "Join session" button appears.
const Duration kJoinWindowLead = Duration(minutes: 10);

/// Firestore-backed appointment (`appointments/{id}`).
///
/// All times are absolute instants (Firestore `Timestamp`, UTC). Call
/// `.toLocal()` only when formatting for display.
class AppointmentV2 {
  final String id;
  final String patientId;
  final String therapistId;
  final String patientName;
  final String therapistName;
  final String requestedBy; // 'patient' | 'therapist'
  final String status;
  final DateTime? scheduledAt;
  final DateTime? proposedAt;
  final int durationMinutes;
  final bool isVirtual;
  final String? meetingUrl;
  final String reason;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? cancelledBy;

  /// True while the document has local writes not yet confirmed by the server.
  final bool hasPendingWrites;

  const AppointmentV2({
    required this.id,
    required this.patientId,
    required this.therapistId,
    required this.patientName,
    required this.therapistName,
    required this.requestedBy,
    required this.status,
    required this.scheduledAt,
    required this.proposedAt,
    required this.durationMinutes,
    required this.isVirtual,
    required this.meetingUrl,
    required this.reason,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.cancelledBy,
    this.hasPendingWrites = false,
  });

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _str(dynamic v, [String fallback = '']) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? fallback : s;
  }

  static int _duration(dynamic v) {
    final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
    if (n == null || n <= 0) return 60;
    return n;
  }

  factory AppointmentV2.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawStatus = _str(d['status'], AppointmentStatus.requested);
    final url = _str(d['meetingUrl']);
    return AppointmentV2(
      id: doc.id,
      patientId: _str(d['patientId']),
      therapistId: _str(d['therapistId']),
      patientName: _str(d['patientName'], 'Patient'),
      therapistName: _str(d['therapistName'], 'Your therapist'),
      requestedBy: _str(d['requestedBy'], 'patient'),
      status: AppointmentStatus.all.contains(rawStatus)
          ? rawStatus
          : AppointmentStatus.requested,
      scheduledAt: _ts(d['scheduledAt']),
      proposedAt: _ts(d['proposedAt']),
      durationMinutes: _duration(d['durationMinutes']),
      isVirtual: d['isVirtual'] == true,
      meetingUrl: url.isEmpty ? null : url,
      reason: _str(d['reason']),
      notes: _str(d['notes']),
      createdAt: _ts(d['createdAt']),
      updatedAt: _ts(d['updatedAt']),
      cancelledBy: d['cancelledBy'] == null ? null : _str(d['cancelledBy']),
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }

  Duration get duration => Duration(minutes: durationMinutes);

  /// The time this appointment is about: the confirmed slot when scheduled,
  /// otherwise the patient's preferred slot.
  DateTime? get effectiveStart => scheduledAt ?? proposedAt;

  DateTime? get scheduledEnd =>
      scheduledAt?.add(duration);

  bool get isRequested => status == AppointmentStatus.requested;
  bool get isScheduled => status == AppointmentStatus.scheduled;
  bool get isTerminal =>
      status == AppointmentStatus.declined ||
      status == AppointmentStatus.cancelled ||
      status == AppointmentStatus.completed ||
      status == AppointmentStatus.noShow;

  /// Scheduled and its end time has passed — therapist must record outcome.
  bool needsOutcome(DateTime now) =>
      isScheduled && scheduledEnd != null && !now.isBefore(scheduledEnd!);

  /// Scheduled session whose start time has been reached.
  bool hasStarted(DateTime now) =>
      isScheduled && scheduledAt != null && !now.isBefore(scheduledAt!);

  /// Inside the window [scheduledAt - 10 min, scheduledAt + duration].
  bool isWithinJoinWindow(DateTime now) {
    if (!isVirtual || !isScheduled || scheduledAt == null) return false;
    final opens = scheduledAt!.subtract(kJoinWindowLead);
    return !now.isBefore(opens) && !now.isAfter(scheduledEnd!);
  }

  /// "Join session" may be shown and used.
  bool canJoin(DateTime now) => isWithinJoinWindow(now) && meetingUrl != null;

  /// In the join window but the Cloud Function has not set the link yet.
  bool isLinkPending(DateTime now) =>
      isWithinJoinWindow(now) && meetingUrl == null;

  /// Either party may cancel a request, or a scheduled session that has not
  /// ended yet.
  bool get canCancel =>
      isRequested ||
      (isScheduled &&
          (scheduledEnd == null || DateTime.now().isBefore(scheduledEnd!)));

  /// Whether [start, start+duration) overlaps this appointment's scheduled slot.
  bool overlaps(DateTime start, int minutes) {
    if (scheduledAt == null) return false;
    final end = start.add(Duration(minutes: minutes));
    return start.isBefore(scheduledEnd!) && scheduledAt!.isBefore(end);
  }
}
