import 'package:cloud_firestore/cloud_firestore.dart';

class Patient {
  final String id;
  final String name;
  final String email;
  final int age;
  final String? therapistId;
  final double currentRiskScore;
  final double riskScore;
  final double wellbeingScore;
  final String lastUpdated;
  final DateTime createdAt;
  final DateTime lastCheckIn;
  final int missedSessions;
  final bool isDemo;

  /// Raw `users.latestRiskScore` (0..100); null when never scored.
  final double? latestRiskScore;

  /// Raw `users.latestWellbeingScore` (0..100); null when never scored.
  final double? latestWellbeingScore;

  /// `users.lastCheckInAt`; null when the patient never checked in.
  final DateTime? lastCheckInAt;

  Patient({
    required this.id,
    required this.name,
    required this.email,
    required this.age,
    this.therapistId,
    required this.currentRiskScore,
    this.riskScore = 0.0,
    this.wellbeingScore = 50.0,
    this.lastUpdated = '',
    required this.createdAt,
    required this.lastCheckIn,
    this.missedSessions = 0,
    this.isDemo = false,
    this.latestRiskScore,
    this.latestWellbeingScore,
    this.lastCheckInAt,
  });

  // JSON Serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'age': age,
      'therapistId': therapistId,
      'currentRiskScore': currentRiskScore,
      'riskScore': riskScore,
      'wellbeingScore': wellbeingScore,
      'lastUpdated': lastUpdated,
      'createdAt': createdAt.toIso8601String(),
      'lastCheckIn': lastCheckIn.toIso8601String(),
      'missedSessions': missedSessions,
      'isDemo': isDemo,
    };
  }

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      age: json['age'] ?? 0,
      therapistId: json['therapistId'],
      currentRiskScore: (json['currentRiskScore'] ?? 0.0).toDouble(),
      riskScore: (json['riskScore'] ?? 0.0).toDouble(),
      wellbeingScore: (json['wellbeingScore'] ?? 50.0).toDouble(),
      lastUpdated: json['lastUpdated'] ?? '',
      createdAt: json['createdAt'] is String 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      lastCheckIn: json['lastCheckIn'] is String
          ? DateTime.parse(json['lastCheckIn'])
          : DateTime.now(),
      missedSessions: json['missedSessions'] ?? 0,
      isDemo: json['isDemo'] ?? false,
    );
  }

  // Map from database
  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      age: map['age'] ?? 0,
      therapistId: map['therapistId'],
      currentRiskScore: (map['riskScore'] ?? 0.0).toDouble(),
      riskScore: (map['riskScore'] ?? 0.0).toDouble(),
      wellbeingScore: (map['wellbeingScore'] ?? 50.0).toDouble(),
      lastUpdated: map['lastUpdated'] ?? '',
      createdAt: DateTime.now(),
      lastCheckIn: DateTime.now(),
      missedSessions: 0,
      isDemo: false,
    );
  }

  /// Build from a Firestore `users/{uid}` document using the contract
  /// fields (docs/DATA_MODEL.md). Risk stays on the legacy 0..1 scale in
  /// [riskScore]/[currentRiskScore] for older widgets; [latestRiskScore]
  /// keeps the raw 0..100 value and is null when the patient was never scored
  /// (never fabricated). [lastCheckInAt] is null when there is no check-in.
  factory Patient.fromFirestore(String uid, Map<String, dynamic> data, {String fallbackName = ''}) {
    double? toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    DateTime? toDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final latestRisk = toDouble(data['latestRiskScore'])?.clamp(0.0, 100.0).toDouble();
    final wellbeing = toDouble(data['latestWellbeingScore'])?.clamp(0.0, 100.0).toDouble();
    final lastCheckInAt = toDate(data['lastCheckInAt']) ?? toDate(data['lastCheckInDate']);
    final name = (data['name'] ?? '').toString().trim();
    return Patient(
      id: uid,
      name: name.isNotEmpty ? name : fallbackName,
      email: (data['email'] ?? '').toString(),
      age: int.tryParse(data['age']?.toString() ?? '') ?? 0,
      therapistId: data['therapistId']?.toString(),
      currentRiskScore: (latestRisk ?? 0) / 100.0,
      riskScore: (latestRisk ?? 0) / 100.0,
      wellbeingScore: wellbeing ?? 50.0,
      createdAt: toDate(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastCheckIn: lastCheckInAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      latestRiskScore: latestRisk,
      latestWellbeingScore: wellbeing,
      lastCheckInAt: lastCheckInAt,
    );
  }

  Patient copyWith({
    String? id,
    String? name,
    String? email,
    int? age,
    String? therapistId,
    double? currentRiskScore,
    DateTime? createdAt,
    DateTime? lastCheckIn,
    int? missedSessions,
    bool? isDemo,
  }) {
    return Patient(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      age: age ?? this.age,
      therapistId: therapistId ?? this.therapistId,
      currentRiskScore: currentRiskScore ?? this.currentRiskScore,
      riskScore: riskScore,
      wellbeingScore: wellbeingScore,
      lastUpdated: lastUpdated,
      latestRiskScore: latestRiskScore,
      latestWellbeingScore: latestWellbeingScore,
      lastCheckInAt: lastCheckInAt,
      createdAt: createdAt ?? this.createdAt,
      lastCheckIn: lastCheckIn ?? this.lastCheckIn,
      missedSessions: missedSessions ?? this.missedSessions,
      isDemo: isDemo ?? this.isDemo,
    );
  }
}
