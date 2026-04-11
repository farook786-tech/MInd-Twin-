class SessionNote {
  final String id;
  final String patientId;
  final String patientName;
  final String therapistId;
  final String therapistName;
  final DateTime sessionDate;
  final int durationMinutes;
  final String? appointmentId;
  
  // Clinical content
  final String chiefComplaint;
  final String subjectiveNotes;
  final String objectiveObservations;
  final String assessment;
  final String plan;
  final String? interventionsUsed;
  final String? homeworkAssigned;
  
  // Risk assessment
  final String riskLevel; // 'low', 'moderate', 'high', 'crisis'
  final String? riskNotes;
  final bool suicidalIdeation;
  final bool homicidalIdeation;
  
  // Session metrics
  final int? patientEngagement; // 1-10 scale
  final String? mood;
  final String? progress; // 'excellent', 'good', 'fair', 'poor'
  
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isLocked; // Locked notes cannot be edited (for legal compliance)

  SessionNote({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.therapistId,
    required this.therapistName,
    required this.sessionDate,
    this.durationMinutes = 50,
    this.appointmentId,
    required this.chiefComplaint,
    required this.subjectiveNotes,
    required this.objectiveObservations,
    required this.assessment,
    required this.plan,
    this.interventionsUsed,
    this.homeworkAssigned,
    this.riskLevel = 'low',
    this.riskNotes,
    this.suicidalIdeation = false,
    this.homicidalIdeation = false,
    this.patientEngagement,
    this.mood,
    this.progress,
    required this.createdAt,
    this.updatedAt,
    this.isLocked = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'therapistId': therapistId,
      'therapistName': therapistName,
      'sessionDate': sessionDate.toIso8601String(),
      'durationMinutes': durationMinutes,
      'appointmentId': appointmentId,
      'chiefComplaint': chiefComplaint,
      'subjectiveNotes': subjectiveNotes,
      'objectiveObservations': objectiveObservations,
      'assessment': assessment,
      'plan': plan,
      'interventionsUsed': interventionsUsed,
      'homeworkAssigned': homeworkAssigned,
      'riskLevel': riskLevel,
      'riskNotes': riskNotes,
      'suicidalIdeation': suicidalIdeation ? 1 : 0,
      'homicidalIdeation': homicidalIdeation ? 1 : 0,
      'patientEngagement': patientEngagement,
      'mood': mood,
      'progress': progress,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isLocked': isLocked ? 1 : 0,
    };
  }

  factory SessionNote.fromMap(Map<String, dynamic> map) {
    return SessionNote(
      id: map['id'] as String,
      patientId: map['patientId'] as String,
      patientName: map['patientName'] as String,
      therapistId: map['therapistId'] as String,
      therapistName: map['therapistName'] as String,
      sessionDate: DateTime.parse(map['sessionDate'] as String),
      durationMinutes: map['durationMinutes'] as int,
      appointmentId: map['appointmentId'] as String?,
      chiefComplaint: map['chiefComplaint'] as String,
      subjectiveNotes: map['subjectiveNotes'] as String,
      objectiveObservations: map['objectiveObservations'] as String,
      assessment: map['assessment'] as String,
      plan: map['plan'] as String,
      interventionsUsed: map['interventionsUsed'] as String?,
      homeworkAssigned: map['homeworkAssigned'] as String?,
      riskLevel: map['riskLevel'] as String,
      riskNotes: map['riskNotes'] as String?,
      suicidalIdeation: (map['suicidalIdeation'] as int) == 1,
      homicidalIdeation: (map['homicidalIdeation'] as int) == 1,
      patientEngagement: map['patientEngagement'] as int?,
      mood: map['mood'] as String?,
      progress: map['progress'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.parse(map['updatedAt'] as String) 
          : null,
      isLocked: (map['isLocked'] as int) == 1,
    );
  }
}
