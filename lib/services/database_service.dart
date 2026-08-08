import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:convert';
import '../models/patient.dart';
import '../models/daily_log.dart';
import '../models/intervention.dart';
import '../models/crisis_alert.dart';
import '../models/appointment.dart';
import '../models/session_note.dart';
import '../models/treatment_plan.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('Database not supported on web');
    }
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('Database not supported on web');
    }
    final dbPath = await getDatabasesPath();
    final dbFile = path.join(dbPath, 'mindtwin.db');

    return await openDatabase(
      dbFile,
      version: 5,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_assessments (
          id TEXT PRIMARY KEY,
          patientId TEXT,
          therapistId TEXT,
          phq9Score INTEGER,
          gad7Score INTEGER,
          answers TEXT,
          createdAt TEXT
        )
      ''');
    }
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          id TEXT PRIMARY KEY,
          senderId TEXT,
          receiverId TEXT,
          body TEXT,
          timestamp TEXT,
          status TEXT
        )
      ''');

      await db.execute('ALTER TABLE crisis_alerts ADD COLUMN patientName TEXT').catchError((_) {});
      await db.execute('ALTER TABLE crisis_alerts ADD COLUMN location TEXT').catchError((_) {});
      await db.execute('ALTER TABLE crisis_alerts ADD COLUMN acknowledged INTEGER DEFAULT 0').catchError((_) {});
      await db.execute('ALTER TABLE crisis_alerts ADD COLUMN acknowledgedAt TEXT').catchError((_) {});
      await db.execute('ALTER TABLE crisis_alerts ADD COLUMN acknowledgedBy TEXT').catchError((_) {});
      await db.execute('ALTER TABLE crisis_alerts ADD COLUMN notes TEXT').catchError((_) {});
    }
    
    if (oldVersion < 3) {
      // Add appointments table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS appointments (
          id TEXT PRIMARY KEY,
          patientId TEXT,
          patientName TEXT,
          therapistId TEXT,
          therapistName TEXT,
          scheduledAt TEXT,
          durationMinutes INTEGER,
          type TEXT,
          status TEXT,
          notes TEXT,
          meetingLink TEXT,
          isVirtual INTEGER,
          createdAt TEXT,
          completedAt TEXT
        )
      ''');
      
      // Add session_notes table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS session_notes (
          id TEXT PRIMARY KEY,
          patientId TEXT,
          patientName TEXT,
          therapistId TEXT,
          therapistName TEXT,
          sessionDate TEXT,
          durationMinutes INTEGER,
          appointmentId TEXT,
          chiefComplaint TEXT,
          subjectiveNotes TEXT,
          objectiveObservations TEXT,
          assessment TEXT,
          plan TEXT,
          interventionsUsed TEXT,
          homeworkAssigned TEXT,
          riskLevel TEXT,
          riskNotes TEXT,
          suicidalIdeation INTEGER,
          homicidalIdeation INTEGER,
          patientEngagement INTEGER,
          mood TEXT,
          progress TEXT,
          createdAt TEXT,
          updatedAt TEXT,
          isLocked INTEGER
        )
      ''');
      
      // Add treatment_plans table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS treatment_plans (
          id TEXT PRIMARY KEY,
          patientId TEXT,
          patientName TEXT,
          therapistId TEXT,
          therapistName TEXT,
          primaryDiagnosis TEXT,
          secondaryDiagnoses TEXT,
          diagnosticCodes TEXT,
          treatmentApproach TEXT,
          sessionFrequency TEXT,
          estimatedDurationWeeks INTEGER,
          goals TEXT,
          includesIndividualTherapy INTEGER,
          includesGroupTherapy INTEGER,
          includesMedication INTEGER,
          medicationNotes TEXT,
          status TEXT,
          createdAt TEXT,
          lastReviewedAt TEXT,
          completedAt TEXT,
          discontinuationReason TEXT,
          progressSummary TEXT,
          overallProgressPercentage INTEGER
        )
      ''');
    }

    if (oldVersion < 4) {
      // Add read-receipt columns to existing message tables.
      await db.execute(
        'ALTER TABLE messages ADD COLUMN is_read INTEGER DEFAULT 0',
      ).catchError((_) {});
      await db.execute(
        'ALTER TABLE messages ADD COLUMN read_at TEXT',
      ).catchError((_) {});
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Patients table
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        name TEXT,
        email TEXT,
        age INTEGER,
        riskScore REAL,
        lastUpdated TEXT,
        wellbeingScore REAL
      )
    ''');

    // Daily logs table
    await db.execute('''
      CREATE TABLE daily_logs (
        id TEXT PRIMARY KEY,
        patientId TEXT,
        sleepHours REAL,
        moodScore INTEGER,
        anxietyLevel INTEGER,
        selfReportScore INTEGER,
        date TEXT,
        FOREIGN KEY (patientId) REFERENCES patients(id)
      )
    ''');

    // Voice journals table
    await db.execute('''
      CREATE TABLE voice_journals (
        id TEXT PRIMARY KEY,
        patientId TEXT,
        filePath TEXT,
        transcription TEXT,
        duration INTEGER,
        date TEXT,
        sentimentScore REAL,
        FOREIGN KEY (patientId) REFERENCES patients(id)
      )
    ''');

    // Crisis alerts table
    await db.execute('''
      CREATE TABLE crisis_alerts (
        id TEXT PRIMARY KEY,
        patientId TEXT,
        patientName TEXT,
        severity TEXT,
        reason TEXT,
        timestamp TEXT,
        status TEXT,
        location TEXT,
        acknowledged INTEGER,
        acknowledgedAt TEXT,
        acknowledgedBy TEXT,
        notes TEXT,
        FOREIGN KEY (patientId) REFERENCES patients(id)
      )
    ''');

    // Direct patient <-> therapist messages
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        senderId TEXT,
        receiverId TEXT,
        body TEXT,
        timestamp TEXT,
        status TEXT,
        is_read INTEGER DEFAULT 0,
        read_at TEXT
      )
    ''');

    // Interventions table
    await db.execute('''
      CREATE TABLE interventions (
        id TEXT PRIMARY KEY,
        patientId TEXT,
        type TEXT,
        description TEXT,
        effectiveness REAL,
        appliedAt TEXT,
        FOREIGN KEY (patientId) REFERENCES patients(id)
      )
    ''');

    // Privacy settings table
    await db.execute('''
      CREATE TABLE privacy_settings (
        id TEXT PRIMARY KEY,
        userId TEXT UNIQUE,
        dataExportDate TEXT,
        dataDeleteDate TEXT,
        privacyPolicyAccepted INTEGER,
        consentDate TEXT
      )
    ''');
    
    // Appointments table
    await db.execute('''
      CREATE TABLE appointments (
        id TEXT PRIMARY KEY,
        patientId TEXT,
        patientName TEXT,
        therapistId TEXT,
        therapistName TEXT,
        scheduledAt TEXT,
        durationMinutes INTEGER,
        type TEXT,
        status TEXT,
        notes TEXT,
        meetingLink TEXT,
        isVirtual INTEGER,
        createdAt TEXT,
        completedAt TEXT,
        FOREIGN KEY (patientId) REFERENCES patients(id)
      )
    ''');
    
    // Session notes table
    await db.execute('''
      CREATE TABLE session_notes (
        id TEXT PRIMARY KEY,
        patientId TEXT,
        patientName TEXT,
        therapistId TEXT,
        therapistName TEXT,
        sessionDate TEXT,
        durationMinutes INTEGER,
        appointmentId TEXT,
        chiefComplaint TEXT,
        subjectiveNotes TEXT,
        objectiveObservations TEXT,
        assessment TEXT,
        plan TEXT,
        interventionsUsed TEXT,
        homeworkAssigned TEXT,
        riskLevel TEXT,
        riskNotes TEXT,
        suicidalIdeation INTEGER,
        homicidalIdeation INTEGER,
        patientEngagement INTEGER,
        mood TEXT,
        progress TEXT,
        createdAt TEXT,
        updatedAt TEXT,
        isLocked INTEGER,
        FOREIGN KEY (patientId) REFERENCES patients(id)
      )
    ''');
    
    // Treatment plans table
    await db.execute('''
      CREATE TABLE treatment_plans (
        id TEXT PRIMARY KEY,
        patientId TEXT,
        patientName TEXT,
        therapistId TEXT,
        therapistName TEXT,
        primaryDiagnosis TEXT,
        secondaryDiagnoses TEXT,
        diagnosticCodes TEXT,
        treatmentApproach TEXT,
        sessionFrequency TEXT,
        estimatedDurationWeeks INTEGER,
        goals TEXT,
        includesIndividualTherapy INTEGER,
        includesGroupTherapy INTEGER,
        includesMedication INTEGER,
        medicationNotes TEXT,
        status TEXT,
        createdAt TEXT,
        lastReviewedAt TEXT,
        completedAt TEXT,
        discontinuationReason TEXT,
        progressSummary TEXT,
        overallProgressPercentage INTEGER,
        FOREIGN KEY (patientId) REFERENCES patients(id)
      )
    ''');

    // Pending assessments queue (offline-first PHQ-9/GAD-7 submissions)
    await db.execute('''
      CREATE TABLE pending_assessments (
        id TEXT PRIMARY KEY,
        patientId TEXT,
        therapistId TEXT,
        phq9Score INTEGER,
        gad7Score INTEGER,
        answers TEXT,
        createdAt TEXT
      )
    ''');
  }

  // ===== PENDING ASSESSMENT QUEUE =====
  Future<void> queuePendingAssessment({
    required String id,
    required String patientId,
    String? therapistId,
    required int phq9Score,
    required int gad7Score,
    required Map<String, dynamic> answers,
  }) async {
    final db = await database;
    await db.insert(
      'pending_assessments',
      {
        'id': id,
        'patientId': patientId,
        'therapistId': therapistId,
        'phq9Score': phq9Score,
        'gad7Score': gad7Score,
        'answers': jsonEncode(answers),
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingAssessments() async {
    final db = await database;
    return db.query('pending_assessments', orderBy: 'createdAt ASC');
  }

  Future<void> deletePendingAssessment(String id) async {
    final db = await database;
    await db.delete(
      'pending_assessments',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ===== PATIENT OPERATIONS =====
  Future<void> insertPatient(Patient patient) async {
    final db = await database;
    await db.insert(
      'patients',
      {
        'id': patient.id,
        'name': patient.name,
        'email': patient.email,
        'age': patient.age,
        'riskScore': patient.riskScore,
        'wellbeingScore': patient.wellbeingScore,
        'lastUpdated': patient.lastUpdated,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Patient?> getPatient(String id) async {
    final db = await database;
    final maps = await db.query('patients', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Patient.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Patient>> getAllPatients() async {
    final db = await database;
    final maps = await db.query('patients');
    return maps.map((map) => Patient.fromMap(map)).toList();
  }

  Future<List<Patient>> getHighRiskPatients() async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'riskScore > ?',
      whereArgs: [0.6],
      orderBy: 'riskScore DESC',
    );
    return maps.map((map) => Patient.fromMap(map)).toList();
  }

  Future<void> updatePatient(Patient patient) async {
    final db = await database;
    await db.update(
      'patients',
      {
        'name': patient.name,
        'email': patient.email,
        'age': patient.age,
        'riskScore': patient.riskScore,
        'wellbeingScore': patient.wellbeingScore,
        'lastUpdated': patient.lastUpdated,
      },
      where: 'id = ?',
      whereArgs: [patient.id],
    );
  }

  Future<void> deletePatient(String patientId) async {
    final db = await database;
    await db.delete('patients', where: 'id = ?', whereArgs: [patientId]);
    await db.delete('daily_logs', where: 'patientId = ?', whereArgs: [patientId]);
    await db.delete('voice_journals', where: 'patientId = ?', whereArgs: [patientId]);
    await db.delete('crisis_alerts', where: 'patientId = ?', whereArgs: [patientId]);
    await db.delete('interventions', where: 'patientId = ?', whereArgs: [patientId]);
    await db.delete('messages', where: 'senderId = ? OR receiverId = ?', whereArgs: [patientId, patientId]);
  }

  // ===== DAILY LOG OPERATIONS =====
  Future<void> insertDailyLog(DailyLog log) async {
    final db = await database;
    await db.insert(
      'daily_logs',
      {
        'id': log.id,
        'patientId': log.patientId,
        'sleepHours': log.sleepHours,
        'moodScore': log.moodScore,
        'anxietyLevel': log.anxietyLevel,
        'selfReportScore': log.selfReportScore,
        'date': log.date,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DailyLog>> getDailyLogs(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'daily_logs',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'date DESC',
    );
    return maps.map((map) => DailyLog.fromMap(map)).toList();
  }

  Future<DailyLog?> getTodayLog(String patientId) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    final maps = await db.query(
      'daily_logs',
      where: 'patientId = ? AND date LIKE ?',
      whereArgs: [patientId, '$today%'],
    );
    if (maps.isNotEmpty) {
      return DailyLog.fromMap(maps.first);
    }
    return null;
  }

  // ===== VOICE JOURNAL OPERATIONS =====
  Future<void> insertVoiceJournal({
    required String id,
    required String patientId,
    required String filePath,
    required String transcription,
    required int duration,
    required String date,
    required double sentimentScore,
  }) async {
    final db = await database;
    await db.insert(
      'voice_journals',
      {
        'id': id,
        'patientId': patientId,
        'filePath': filePath,
        'transcription': transcription,
        'duration': duration,
        'date': date,
        'sentimentScore': sentimentScore,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getVoiceJournals(String patientId) async {
    final db = await database;
    return await db.query(
      'voice_journals',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'date DESC',
    );
  }

  // ===== CRISIS ALERT OPERATIONS =====
  Future<void> insertCrisisAlert(CrisisAlert alert) async {
    final db = await database;
    await db.insert(
      'crisis_alerts',
      {
        'id': alert.id,
        'patientId': alert.patientId,
        'patientName': alert.patientName,
        'severity': alert.severity,
        'reason': alert.reason,
        'timestamp': alert.timestamp.toIso8601String(),
        'status': alert.status,
        'location': alert.location,
        'acknowledged': alert.acknowledged ? 1 : 0,
        'acknowledgedAt': alert.acknowledgedAt?.toIso8601String(),
        'acknowledgedBy': alert.acknowledgedBy,
        'notes': alert.notes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CrisisAlert>> getCrisisAlerts(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'crisis_alerts',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => CrisisAlert.fromMap(map)).toList();
  }

  Future<List<CrisisAlert>> getAllCrisisAlerts() async {
    final db = await database;
    final maps = await db.query(
      'crisis_alerts',
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => CrisisAlert.fromMap(map)).toList();
  }

  Future<void> updateCrisisAlertStatus(
    String alertId,
    String status, {
    String? acknowledgedBy,
    String? notes,
  }) async {
    final db = await database;
    await db.update(
      'crisis_alerts',
      {
        'status': status,
        'acknowledged': status == 'resolved' || status == 'acknowledged' ? 1 : 0,
        'acknowledgedAt': DateTime.now().toIso8601String(),
        'acknowledgedBy': acknowledgedBy,
        'notes': notes,
      },
      where: 'id = ?',
      whereArgs: [alertId],
    );
  }

  // ===== MESSAGE OPERATIONS =====
  Future<void> insertMessage({
    required String id,
    required String senderId,
    required String receiverId,
    required String body,
    required String timestamp,
    String status = 'sent',
    int isRead = 0,
    String? readAt,
  }) async {
    final db = await database;
    await db.insert(
      'messages',
      {
        'id': id,
        'senderId': senderId,
        'receiverId': receiverId,
        'body': body,
        'timestamp': timestamp,
        'status': status,
        'is_read': isRead,
        'read_at': readAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getConversation(
    String userA,
    String userB,
  ) async {
    final db = await database;
    return db.query(
      'messages',
      where:
          '(senderId = ? AND receiverId = ?) OR (senderId = ? AND receiverId = ?)',
      whereArgs: [userA, userB, userB, userA],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> getUnreadMessageCount(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE receiverId = ? AND status = ?',
      [userId, 'sent'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markConversationAsRead(String userId, String otherUserId) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': 'read', 'is_read': 1, 'read_at': DateTime.now().toIso8601String()},
      where: 'receiverId = ? AND senderId = ?',
      whereArgs: [userId, otherUserId],
    );
  }

  // ===== INTERVENTION OPERATIONS =====
  Future<void> insertIntervention(Intervention intervention) async {
    final db = await database;
    await db.insert(
      'interventions',
      {
        'id': intervention.id,
        'patientId': intervention.patientId,
        'type': intervention.type.name,
        'description': intervention.description,
        'effectiveness': intervention.projectedRiskReduction,
        'appliedAt': intervention.timestamp.toIso8601String(),
      },
    );
  }

  Future<List<Intervention>> getInterventions(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'interventions',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'appliedAt DESC',
    );
    return maps.map((map) => Intervention.fromMap(map)).toList();
  }

  // ===== PRIVACY OPERATIONS =====
  Future<void> setPrivacySettings(
    String userId, {
    bool privacyPolicyAccepted = false,
  }) async {
    final db = await database;
    await db.insert(
      'privacy_settings',
      {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'userId': userId,
        'privacyPolicyAccepted': privacyPolicyAccepted ? 1 : 0,
        'consentDate': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getPrivacySettings(String userId) async {
    final db = await database;
    final maps = await db.query(
      'privacy_settings',
      where: 'userId = ?',
      whereArgs: [userId],
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<void> setDataExportDate(String userId) async {
    final db = await database;
    await db.update(
      'privacy_settings',
      {'dataExportDate': DateTime.now().toIso8601String()},
      where: 'userId = ?',
      whereArgs: [userId],
    );
  }

  Future<void> setDataDeleteDate(String userId) async {
    final db = await database;
    await db.update(
      'privacy_settings',
      {'dataDeleteDate': DateTime.now().toIso8601String()},
      where: 'userId = ?',
      whereArgs: [userId],
    );
  }

  // ===== UTILITY OPERATIONS =====
  Future<void> deleteAllData() async {
    final db = await database;
    await db.delete('daily_logs');
    await db.delete('voice_journals');
    await db.delete('crisis_alerts');
    await db.delete('interventions');
    await db.delete('patients');
  }

  Future<void> deleteUserData(String userId) async {
    final db = await database;
    await db.delete('daily_logs', where: 'patientId = ?', whereArgs: [userId]);
    await db.delete('voice_journals', where: 'patientId = ?', whereArgs: [userId]);
    await db.delete('crisis_alerts', where: 'patientId = ?', whereArgs: [userId]);
    await db.delete('interventions', where: 'patientId = ?', whereArgs: [userId]);
    await db.delete(
      'messages',
      where: 'senderId = ? OR receiverId = ?',
      whereArgs: [userId, userId],
    );
    await db.delete('privacy_settings', where: 'userId = ?', whereArgs: [userId]);
    await db.delete('patients', where: 'id = ?', whereArgs: [userId]);
  }

  Future<int> getPatientCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM patients');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ===== APPOINTMENT OPERATIONS =====
  Future<void> insertAppointment(Appointment appointment) async {
    final db = await database;
    await db.insert(
      'appointments',
      appointment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Appointment>> getAppointments(String userId, {bool isTherapist = false}) async {
    final db = await database;
    final maps = await db.query(
      'appointments',
      where: isTherapist ? 'therapistId = ?' : 'patientId = ?',
      whereArgs: [userId],
      orderBy: 'scheduledAt DESC',
    );
    return maps.map((map) => Appointment.fromMap(map)).toList();
  }

  Future<List<Appointment>> getUpcomingAppointments(String userId, {bool isTherapist = false}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final maps = await db.query(
      'appointments',
      where: isTherapist 
          ? 'therapistId = ? AND scheduledAt >= ? AND status = ?'
          : 'patientId = ? AND scheduledAt >= ? AND status = ?',
      whereArgs: [userId, now, 'scheduled'],
      orderBy: 'scheduledAt ASC',
    );
    return maps.map((map) => Appointment.fromMap(map)).toList();
  }

  Future<void> updateAppointment(Appointment appointment) async {
    final db = await database;
    await db.update(
      'appointments',
      appointment.toMap(),
      where: 'id = ?',
      whereArgs: [appointment.id],
    );
  }

  Future<void> deleteAppointment(String appointmentId) async {
    final db = await database;
    await db.delete('appointments', where: 'id = ?', whereArgs: [appointmentId]);
  }

  // ===== SESSION NOTE OPERATIONS =====
  Future<void> insertSessionNote(SessionNote note) async {
    final db = await database;
    await db.insert(
      'session_notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SessionNote>> getSessionNotes(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'session_notes',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'sessionDate DESC',
    );
    return maps.map((map) => SessionNote.fromMap(map)).toList();
  }

  Future<SessionNote?> getSessionNote(String noteId) async {
    final db = await database;
    final maps = await db.query(
      'session_notes',
      where: 'id = ?',
      whereArgs: [noteId],
    );
    if (maps.isNotEmpty) {
      return SessionNote.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateSessionNote(SessionNote note) async {
    final db = await database;
    await db.update(
      'session_notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteSessionNote(String noteId) async {
    final db = await database;
    await db.delete('session_notes', where: 'id = ?', whereArgs: [noteId]);
  }

  // ===== TREATMENT PLAN OPERATIONS =====
  Future<void> insertTreatmentPlan(TreatmentPlan plan) async {
    final db = await database;
    final map = plan.toMap();
    // Convert goals list to JSON string
    map['goals'] = jsonEncode(map['goals']);
    await db.insert(
      'treatment_plans',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TreatmentPlan?> getActiveTreatmentPlan(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'treatment_plans',
      where: 'patientId = ? AND status = ?',
      whereArgs: [patientId, 'active'],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      final map = Map<String, dynamic>.from(maps.first);
      // Parse goals JSON string
      if (map['goals'] is String) {
        final goalsStr = map['goals'] as String;
        map['goals'] = goalsStr.isNotEmpty ? jsonDecode(goalsStr) : [];
      }
      return TreatmentPlan.fromMap(map);
    }
    return null;
  }

  Future<List<TreatmentPlan>> getTreatmentPlans(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'treatment_plans',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) {
      final map = Map<String, dynamic>.from(m);
      if (map['goals'] is String) {
        final goalsStr = map['goals'] as String;
        map['goals'] = goalsStr.isNotEmpty ? jsonDecode(goalsStr) : [];
      }
      return TreatmentPlan.fromMap(map);
    }).toList();
  }

  Future<void> updateTreatmentPlan(TreatmentPlan plan) async {
    final db = await database;
    final map = plan.toMap();
    map['goals'] = jsonEncode(map['goals']);
    await db.update(
      'treatment_plans',
      map,
      where: 'id = ?',
      whereArgs: [plan.id],
    );
  }

  Future<void> deleteTreatmentPlan(String planId) async {
    final db = await database;
    await db.delete('treatment_plans', where: 'id = ?', whereArgs: [planId]);
  }
}
