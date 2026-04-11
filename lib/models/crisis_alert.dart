class CrisisAlert {
  final String id;
  final String patientId;
  final String patientName;
  final String severity; // 'low', 'medium', 'critical'
  final String reason; // Why the alert was triggered
  final DateTime timestamp;
  final String location; // GPS coordinates or "Unknown"
  final String status; // 'pending', 'acknowledged', 'resolved'
  final bool acknowledged;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy; // therapistId
  final String? notes;

  CrisisAlert({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.severity = 'critical',
    this.reason = 'Direct patient request',
    required this.timestamp,
    this.location = 'Unknown',
    this.status = 'pending',
    this.acknowledged = false,
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'severity': severity,
      'reason': reason,
      'timestamp': timestamp.toIso8601String(),
      'location': location,
      'status': status,
      'acknowledged': acknowledged,
      'acknowledgedAt': acknowledgedAt?.toIso8601String(),
      'acknowledgedBy': acknowledgedBy,
      'notes': notes,
    };
  }

  factory CrisisAlert.fromJson(Map<String, dynamic> json) {
    return CrisisAlert(
      id: json['id'] ?? '',
      patientId: json['patientId'] ?? '',
      patientName: json['patientName'] ?? '',
      severity: json['severity'] ?? 'critical',
      reason: json['reason'] ?? 'Direct patient request',
      timestamp: json['timestamp'] is String
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      location: json['location'] ?? 'Unknown',
      status: json['status'] ?? 'pending',
      acknowledged: json['acknowledged'] ?? false,
      acknowledgedAt: json['acknowledgedAt'] is String
          ? DateTime.parse(json['acknowledgedAt'])
          : null,
      acknowledgedBy: json['acknowledgedBy'],
      notes: json['notes'],
    );
  }

  factory CrisisAlert.fromMap(Map<String, dynamic> map) {
    return CrisisAlert(
      id: map['id'] ?? '',
      patientId: map['patientId'] ?? '',
      patientName: map['patientName'] ?? 'Patient',
      severity: map['severity'] ?? 'critical',
      reason: map['reason'] ?? 'Direct patient request',
      timestamp: map['timestamp'] is String
          ? DateTime.parse(map['timestamp'])
          : DateTime.now(),
      location: map['location'] ?? 'Unknown',
      status: map['status'] ?? 'pending',
      acknowledged: map['acknowledged'] == 1,
      acknowledgedAt: map['acknowledgedAt'] is String
          ? DateTime.parse(map['acknowledgedAt'])
          : null,
      acknowledgedBy: map['acknowledgedBy'],
      notes: map['notes'],
    );
  }
}
