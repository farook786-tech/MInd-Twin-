enum InterventionType {
  doNothing,
  callPatient,
  increaseSessions,
  groupTherapy,
  psychiatristReferral,
}

class Intervention {
  final String id;
  final String patientId;
  final String therapistId;
  final InterventionType type;
  final DateTime timestamp;
  final double projectedRiskReduction; // Expected risk score improvement
  final String description;
  final bool isSimulated; // True if this is a "what-if" simulation
  final DateTime? scheduledDate;
  final bool completed;

  Intervention({
    required this.id,
    required this.patientId,
    required this.therapistId,
    required this.type,
    required this.timestamp,
    required this.projectedRiskReduction,
    required this.description,
    this.isSimulated = false,
    this.scheduledDate,
    this.completed = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientId': patientId,
      'therapistId': therapistId,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'projectedRiskReduction': projectedRiskReduction,
      'description': description,
      'isSimulated': isSimulated,
      'scheduledDate': scheduledDate?.toIso8601String(),
      'completed': completed,
    };
  }

  factory Intervention.fromJson(Map<String, dynamic> json) {
    return Intervention(
      id: json['id'] ?? '',
      patientId: json['patientId'] ?? '',
      therapistId: json['therapistId'] ?? '',
      type: InterventionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => InterventionType.doNothing,
      ),
      timestamp: json['timestamp'] is String
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      projectedRiskReduction: (json['projectedRiskReduction'] ?? 0.0).toDouble(),
      description: json['description'] ?? '',
      isSimulated: json['isSimulated'] ?? false,
      scheduledDate: json['scheduledDate'] is String
          ? DateTime.parse(json['scheduledDate'])
          : null,
      completed: json['completed'] ?? false,
    );
  }

  factory Intervention.fromMap(Map<String, dynamic> map) {
    return Intervention(
      id: map['id'] ?? '',
      patientId: map['patientId'] ?? '',
      therapistId: '',
      type: InterventionType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => InterventionType.doNothing,
      ),
      timestamp: DateTime.now(),
      projectedRiskReduction: (map['effectiveness'] ?? 0.0).toDouble(),
      description: map['description'] ?? '',
      isSimulated: false,
      scheduledDate: null,
      completed: false,
    );
  }

  // Clinical evidence-based constants for simulation
  static Map<InterventionType, double> get riskReductionConstants {
    return {
      InterventionType.doNothing: 0.0,
      InterventionType.callPatient: 0.15, // 15% risk reduction
      InterventionType.increaseSessions: 0.50, // 50% risk reduction
      InterventionType.groupTherapy: 0.30, // 30% risk reduction
      InterventionType.psychiatristReferral: 0.60, // 60% risk reduction
    };
  }

  static String getInterventionLabel(InterventionType type) {
    switch (type) {
      case InterventionType.doNothing:
        return 'Do Nothing';
      case InterventionType.callPatient:
        return 'Call Patient';
      case InterventionType.increaseSessions:
        return 'Increase Sessions';
      case InterventionType.groupTherapy:
        return 'Group Therapy';
      case InterventionType.psychiatristReferral:
        return 'Psychiatrist Referral';
    }
  }
}
