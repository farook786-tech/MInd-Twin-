class Appointment {
  final String id;
  final String patientId;
  final String patientName;
  final String therapistId;
  final String therapistName;
  final DateTime scheduledAt;
  final int durationMinutes;
  final String type; // 'individual', 'group', 'initial', 'followup'
  final String status; // 'scheduled', 'completed', 'cancelled', 'noshow'
  final String? notes;
  final String? meetingLink;
  final bool isVirtual;
  final DateTime createdAt;
  final DateTime? completedAt;

  Appointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.therapistId,
    required this.therapistName,
    required this.scheduledAt,
    this.durationMinutes = 50,
    required this.type,
    this.status = 'scheduled',
    this.notes,
    this.meetingLink,
    this.isVirtual = false,
    required this.createdAt,
    this.completedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'therapistId': therapistId,
      'therapistName': therapistName,
      'scheduledAt': scheduledAt.toIso8601String(),
      'durationMinutes': durationMinutes,
      'type': type,
      'status': status,
      'notes': notes,
      'meetingLink': meetingLink,
      'isVirtual': isVirtual ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory Appointment.fromMap(Map<String, dynamic> map) {
    return Appointment(
      id: map['id'] as String,
      patientId: map['patientId'] as String,
      patientName: map['patientName'] as String,
      therapistId: map['therapistId'] as String,
      therapistName: map['therapistName'] as String,
      scheduledAt: DateTime.parse(map['scheduledAt'] as String),
      durationMinutes: map['durationMinutes'] as int,
      type: map['type'] as String,
      status: map['status'] as String,
      notes: map['notes'] as String?,
      meetingLink: map['meetingLink'] as String?,
      isVirtual: (map['isVirtual'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      completedAt: map['completedAt'] != null 
          ? DateTime.parse(map['completedAt'] as String) 
          : null,
    );
  }

  Appointment copyWith({
    String? id,
    String? patientId,
    String? patientName,
    String? therapistId,
    String? therapistName,
    DateTime? scheduledAt,
    int? durationMinutes,
    String? type,
    String? status,
    String? notes,
    String? meetingLink,
    bool? isVirtual,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return Appointment(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      therapistId: therapistId ?? this.therapistId,
      therapistName: therapistName ?? this.therapistName,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      type: type ?? this.type,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      meetingLink: meetingLink ?? this.meetingLink,
      isVirtual: isVirtual ?? this.isVirtual,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
