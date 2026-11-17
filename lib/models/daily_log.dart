/// One check-in day on a higher-is-better scale for the ML services.
///
/// Clinical values are NULLABLE: a value that was not recorded is null, never
/// a fabricated "neutral" default (fabricated defaults silently pulled risk
/// estimates toward normal).
class DailyLog {
  final String id;
  final String patientId;
  final DateTime timestamp;
  final double? moodScore; // 0-10, 10 = best
  final double? sleepHours; // 0-14
  final double? energyLevel; // 0-10, 10 = best
  final double? anxietyLevel; // 0-10, 10 = most anxious
  final double? selfReportScore; // 0-100
  final double? voiceEnergy; // 0-1 (from audio analysis)
  final double? textSentiment; // -1 to 1
  final int appOpenCount; // Passive behavior
  final double? wellbeingScore; // 0-100
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
    this.anxietyLevel,
    this.selfReportScore,
    this.voiceEnergy,
    this.textSentiment,
    this.appOpenCount = 0,
    this.wellbeingScore,
    this.date = '',
    this.notes,
    this.audioUrl,
  });

  static double? _num(dynamic v) {
    if (v is num && v.isFinite) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

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
    final ts = json['timestamp'] is String ? DateTime.tryParse(json['timestamp'] as String) : null;
    final date = (json['date'] ?? '') as String;
    return DailyLog(
      id: json['id'] ?? '',
      patientId: json['patientId'] ?? '',
      timestamp: ts ?? DateTime.tryParse(date) ?? DateTime.fromMillisecondsSinceEpoch(0),
      moodScore: _num(json['moodScore']),
      sleepHours: _num(json['sleepHours']),
      energyLevel: _num(json['energyLevel']),
      anxietyLevel: _num(json['anxietyLevel']),
      selfReportScore: _num(json['selfReportScore']),
      voiceEnergy: _num(json['voiceEnergy']),
      textSentiment: _num(json['textSentiment']),
      appOpenCount: (json['appOpenCount'] as num?)?.toInt() ?? 0,
      wellbeingScore: _num(json['wellbeingScore']),
      date: date,
      notes: json['notes'],
      audioUrl: json['audioUrl'],
    );
  }

  /// From the local SQLite row (which has no timestamp/energy columns).
  factory DailyLog.fromMap(Map<String, dynamic> map) {
    final date = (map['date'] ?? '') as String;
    return DailyLog(
      id: map['id'] ?? '',
      patientId: map['patientId'] ?? '',
      // Use the stored date, not "now": a stale log must look stale.
      timestamp: DateTime.tryParse(date) ?? DateTime.fromMillisecondsSinceEpoch(0),
      moodScore: _num(map['moodScore']),
      sleepHours: _num(map['sleepHours']),
      energyLevel: null,
      anxietyLevel: _num(map['anxietyLevel']),
      selfReportScore: _num(map['selfReportScore']),
      date: date,
    );
  }
}
