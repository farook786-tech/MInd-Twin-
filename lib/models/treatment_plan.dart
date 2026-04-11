import 'dart:convert';

class TreatmentGoal {
  final String id;
  final String description;
  final String targetDate;
  final String status; // 'not-started', 'in-progress', 'achieved', 'discontinued'
  final String? progressNotes;
  final int? progressPercentage; // 0-100

  TreatmentGoal({
    required this.id,
    required this.description,
    required this.targetDate,
    this.status = 'not-started',
    this.progressNotes,
    this.progressPercentage,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'targetDate': targetDate,
      'status': status,
      'progressNotes': progressNotes,
      'progressPercentage': progressPercentage,
    };
  }

  factory TreatmentGoal.fromJson(Map<String, dynamic> json) {
    return TreatmentGoal(
      id: json['id'] as String,
      description: json['description'] as String,
      targetDate: json['targetDate'] as String,
      status: json['status'] as String? ?? 'not-started',
      progressNotes: json['progressNotes'] as String?,
      progressPercentage: json['progressPercentage'] as int?,
    );
  }
}

class TreatmentPlan {
  final String id;
  final String patientId;
  final String patientName;
  final String therapistId;
  final String therapistName;
  
  // Diagnosis
  final String primaryDiagnosis;
  final String? secondaryDiagnoses;
  final String? diagnosticCodes; // ICD-10 codes
  
  // Treatment details
  final String treatmentApproach; // 'CBT', 'DBT', 'Psychodynamic', etc.
  final String sessionFrequency; // 'weekly', 'biweekly', 'monthly'
  final int estimatedDurationWeeks;
  final List<TreatmentGoal> goals;
  
  // Modalities
  final bool includesIndividualTherapy;
  final bool includesGroupTherapy;
  final bool includesMedication;
  final String? medicationNotes;
  
  // Status
  final String status; // 'active', 'completed', 'discontinued', 'on-hold'
  final DateTime createdAt;
  final DateTime? lastReviewedAt;
  final DateTime? completedAt;
  final String? discontinuationReason;
  
  // Progress
  final String? progressSummary;
  final int? overallProgressPercentage; // 0-100

  TreatmentPlan({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.therapistId,
    required this.therapistName,
    required this.primaryDiagnosis,
    this.secondaryDiagnoses,
    this.diagnosticCodes,
    required this.treatmentApproach,
    required this.sessionFrequency,
    required this.estimatedDurationWeeks,
    required this.goals,
    this.includesIndividualTherapy = true,
    this.includesGroupTherapy = false,
    this.includesMedication = false,
    this.medicationNotes,
    this.status = 'active',
    required this.createdAt,
    this.lastReviewedAt,
    this.completedAt,
    this.discontinuationReason,
    this.progressSummary,
    this.overallProgressPercentage,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'therapistId': therapistId,
      'therapistName': therapistName,
      'primaryDiagnosis': primaryDiagnosis,
      'secondaryDiagnoses': secondaryDiagnoses,
      'diagnosticCodes': diagnosticCodes,
      'treatmentApproach': treatmentApproach,
      'sessionFrequency': sessionFrequency,
      'estimatedDurationWeeks': estimatedDurationWeeks,
      'goals': goals.map((g) => g.toJson()).toList(),
      'includesIndividualTherapy': includesIndividualTherapy ? 1 : 0,
      'includesGroupTherapy': includesGroupTherapy ? 1 : 0,
      'includesMedication': includesMedication ? 1 : 0,
      'medicationNotes': medicationNotes,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'lastReviewedAt': lastReviewedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'discontinuationReason': discontinuationReason,
      'progressSummary': progressSummary,
      'overallProgressPercentage': overallProgressPercentage,
    };
  }

  factory TreatmentPlan.fromMap(Map<String, dynamic> map) {
    List<TreatmentGoal> goals = [];
    if (map['goals'] is String) {
      // Parse JSON string
      final goalsJson = map['goals'] as String;
      if (goalsJson.isNotEmpty) {
        try {
          final dynamic decoded = jsonDecode(goalsJson);
          if (decoded is List) {
            goals = decoded.map((g) => TreatmentGoal.fromJson(g as Map<String, dynamic>)).toList();
          }
        } catch (e) {
          goals = [];
        }
      }
    } else if (map['goals'] is List) {
      goals = (map['goals'] as List)
          .map((g) => TreatmentGoal.fromJson(g as Map<String, dynamic>))
          .toList();
    }

    return TreatmentPlan(
      id: map['id'] as String,
      patientId: map['patientId'] as String,
      patientName: map['patientName'] as String,
      therapistId: map['therapistId'] as String,
      therapistName: map['therapistName'] as String,
      primaryDiagnosis: map['primaryDiagnosis'] as String,
      secondaryDiagnoses: map['secondaryDiagnoses'] as String?,
      diagnosticCodes: map['diagnosticCodes'] as String?,
      treatmentApproach: map['treatmentApproach'] as String,
      sessionFrequency: map['sessionFrequency'] as String,
      estimatedDurationWeeks: map['estimatedDurationWeeks'] as int,
      goals: goals,
      includesIndividualTherapy: (map['includesIndividualTherapy'] as int) == 1,
      includesGroupTherapy: (map['includesGroupTherapy'] as int) == 1,
      includesMedication: (map['includesMedication'] as int) == 1,
      medicationNotes: map['medicationNotes'] as String?,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      lastReviewedAt: map['lastReviewedAt'] != null 
          ? DateTime.parse(map['lastReviewedAt'] as String) 
          : null,
      completedAt: map['completedAt'] != null 
          ? DateTime.parse(map['completedAt'] as String) 
          : null,
      discontinuationReason: map['discontinuationReason'] as String?,
      progressSummary: map['progressSummary'] as String?,
      overallProgressPercentage: map['overallProgressPercentage'] as int?,
    );
  }
}
