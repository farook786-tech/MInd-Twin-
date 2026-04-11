class DailyLog {
  final String id;
  final String patientId;
  final DateTime timestamp;
  final double moodScore; // 0-10
  final double sleepHours; // 0-12
  final double energyLevel; // 0-10
  final double anxietyLevel; // 0-10
  final double selfReportScore; // 0-100
  final double voiceEnergy; // 0-1 (from audio analysis)
  final double textSentiment; // -1 to 1
  final int appOpenCount; // Passive behavior
  final double wellbeingScore; // Computed by Digital Twin Engine
  final String date;
  final String? notes;
  final String? audioUrl;

  DailyLog({
    required this.id,
    required this.patientId,
    required this.timestamp,
    required this.moodScore,
    required this.sleepHours,
    required this.energyLevel,
    this.anxietyLevel = 5.0,
    this.selfReportScore = 50.0,
    this.voiceEnergy = 0.5,
    this.textSentiment = 0.0,
    this.appOpenCount = 0,
    required this.wellbeingScore,
    this.date = '',
    this.notes,
    this.audioUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientId': patientId,
      'timestamp': timestamp.toIso8601String(),
      'moodScore': moodScore,
      'sleepHours': sleepHours,
      'energyLevel': energyLevel,
      'anxietyLevel': anxietyLevel,
      'selfReportScore': selfReportScore,
      'voiceEnergy': voiceEnergy,
      'textSentiment': textSentiment,
      'appOpenCount': appOpenCount,
      'wellbeingScore': wellbeingScore,
      'date': date,
      'notes': notes,
      'audioUrl': audioUrl,
    };
  }

  factory DailyLog.fromJson(Map<String, dynamic> json) {
    return DailyLog(
      id: json['id'] ?? '',
      patientId: json['patientId'] ?? '',
      timestamp: json['timestamp'] is String
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      moodScore: (json['moodScore'] ?? 5.0).toDouble(),
      sleepHours: (json['sleepHours'] ?? 7.0).toDouble(),
      energyLevel: (json['energyLevel'] ?? 5.0).toDouble(),
      anxietyLevel: (json['anxietyLevel'] ?? 5.0).toDouble(),
      selfReportScore: (json['selfReportScore'] ?? 50.0).toDouble(),
      voiceEnergy: (json['voiceEnergy'] ?? 0.5).toDouble(),
      textSentiment: (json['textSentiment'] ?? 0.0).toDouble(),
      appOpenCount: json['appOpenCount'] ?? 0,
      wellbeingScore: (json['wellbeingScore'] ?? 0.5).toDouble(),
      date: json['date'] ?? '',
      notes: json['notes'],
      audioUrl: json['audioUrl'],
    );
  }

  factory DailyLog.fromMap(Map<String, dynamic> map) {
    return DailyLog(
      id: map['id'] ?? '',
      patientId: map['patientId'] ?? '',
      timestamp: DateTime.now(),
      moodScore: (map['moodScore'] ?? 5).toDouble(),
      sleepHours: (map['sleepHours'] ?? 7.0).toDouble(),
      energyLevel: 5.0,
      anxietyLevel: (map['anxietyLevel'] ?? 5).toDouble(),
      selfReportScore: (map['selfReportScore'] ?? 50).toDouble(),
      voiceEnergy: 0.5,
      textSentiment: 0.0,
      appOpenCount: 0,
      wellbeingScore: 50.0,
      date: map['date'] ?? '',
      notes: null,
      audioUrl: null,
    );
  }
}
