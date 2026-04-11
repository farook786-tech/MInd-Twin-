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

  // Demo Patient: James K. - 91% risk, 3 missed sessions, declining mood
  factory Patient.demoJamesK() {
    return Patient(
      id: 'demo_james_k',
      name: 'James K.',
      email: 'james.k@demo.mindtwin.ai',
      age: 34,
      therapistId: 'therapist_001',
      currentRiskScore: 0.91,
      riskScore: 0.91,
      wellbeingScore: 25.0,
      lastUpdated: DateTime.now().toIso8601String(),
      createdAt: DateTime.now().subtract(const Duration(days: 180)),
      lastCheckIn: DateTime.now().subtract(const Duration(days: 5)),
      missedSessions: 3,
      isDemo: true,
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
      createdAt: createdAt ?? this.createdAt,
      lastCheckIn: lastCheckIn ?? this.lastCheckIn,
      missedSessions: missedSessions ?? this.missedSessions,
      isDemo: isDemo ?? this.isDemo,
    );
  }
}
