let Database = null;
try {
  Database = require('better-sqlite3');
} catch (error) {
  console.warn(
    '[Database] better-sqlite3 could not be loaded. Running without SQLite.',
    error && error.message ? error.message : error
  );
}
const path = require('path');
const fs = require('fs');

class DatabaseService {
  constructor() {
    this.db = null;
  }

  static getInstance() {
    if (!DatabaseService.instance) {
      DatabaseService.instance = new DatabaseService();
    }
    return DatabaseService.instance;
  }

  async initialize() {
    if (!Database) {
      console.warn('[Database] SQLite unavailable. Skipping local DB initialization.');
      this.db = null;
      return;
    }

    const dbPath = path.join(__dirname, '../../mindtwin.db');
    console.log('Initializing database at:', dbPath);

    try {
      this.db = new Database(dbPath);
      this.db.pragma('journal_mode = WAL');

      await this.createTables();
      console.log('✅ Database initialized successfully');
    } catch (error) {
      this.db = null;
      console.warn(
        '[Database] SQLite initialization failed. Continuing without SQLite.',
        error && error.message ? error.message : error
      );
    }
  }

  async createTables() {
    if (!this.db) {
      console.warn('[Database] createTables skipped because SQLite is unavailable.');
      return;
    }

    const tables = [
      // Users table (both therapists and patients)
      `CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'patient',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )`,

      // Patient profiles
      `CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL UNIQUE,
        age INTEGER,
        therapist_id TEXT,
        risk_score REAL DEFAULT 0.5,
        wellbeing_score REAL DEFAULT 50,
        current_risk_score REAL DEFAULT 0.5,
        last_check_in DATETIME,
        missed_sessions INTEGER DEFAULT 0,
        is_demo BOOLEAN DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (therapist_id) REFERENCES users(id)
      )`,

      // Daily logs
      `CREATE TABLE IF NOT EXISTS daily_logs (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        mood_score REAL,
        sleep_hours REAL,
        anxiety_level REAL,
        wellbeing_score REAL,
        energy_level REAL,
        self_report_score REAL,
        notes TEXT,
        date TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id)
      )`,

      // Crisis alerts
      `CREATE TABLE IF NOT EXISTS crisis_alerts (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        alert_type TEXT,
        severity REAL,
        description TEXT,
        resolved BOOLEAN DEFAULT 0,
        resolved_at DATETIME,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id)
      )`,

      // Messages
      `CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL,
        message_type TEXT DEFAULT 'text',
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (sender_id) REFERENCES users(id)
      )`,

      // Conversations
      `CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        therapist_id TEXT,
        title TEXT,
        last_message_at DATETIME,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id),
        FOREIGN KEY (therapist_id) REFERENCES users(id)
      )`,

      // Voice journals
      `CREATE TABLE IF NOT EXISTS voice_journals (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        file_path TEXT,
        duration REAL,
        transcript TEXT,
        mood_detected TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id)
      )`,

      // Interventions log
      `CREATE TABLE IF NOT EXISTS interventions (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        therapist_id TEXT,
        intervention_type TEXT,
        description TEXT,
        status TEXT DEFAULT 'pending',
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id),
        FOREIGN KEY (therapist_id) REFERENCES users(id)
      )`,

      // Privacy settings
      `CREATE TABLE IF NOT EXISTS privacy_settings (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL UNIQUE,
        hipaa_compliant_sharing BOOLEAN DEFAULT 1,
        federated_research BOOLEAN DEFAULT 0,
        anonymous_data_sharing BOOLEAN DEFAULT 1,
        third_party_analytics BOOLEAN DEFAULT 0,
        last_data_export DATETIME,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )`,

      // Device tokens for push notifications
      `CREATE TABLE IF NOT EXISTS device_tokens (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        token TEXT NOT NULL,
        platform TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )`,

      // Shared check-ins for cross-device patient -> therapist sync by clinic code
      `CREATE TABLE IF NOT EXISTS shared_checkins (
        id TEXT PRIMARY KEY,
        clinic_code TEXT NOT NULL,
        patient_external_id TEXT NOT NULL,
        patient_name TEXT,
        patient_email TEXT,
        mood_score REAL,
        sleep_hours REAL,
        anxiety_level REAL,
        energy_level REAL,
        heart_rate REAL,
        activity_level REAL,
        screen_time_hours REAL,
        risk_score REAL,
        risk_state TEXT,
        wellbeing_score REAL,
        notes TEXT,
        intervention_title TEXT,
        companion_message TEXT,
        explainability_json TEXT,
        source_platform TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )`,

      // Shared appointment booking table for patient -> therapist workflow
      `CREATE TABLE IF NOT EXISTS shared_appointments (
        id TEXT PRIMARY KEY,
        clinic_code TEXT NOT NULL,
        patient_external_id TEXT NOT NULL,
        patient_name TEXT,
        therapist_external_id TEXT,
        therapist_name TEXT,
        scheduled_at TEXT NOT NULL,
        duration_minutes INTEGER DEFAULT 50,
        type TEXT DEFAULT 'followup',
        status TEXT DEFAULT 'scheduled',
        patient_seen INTEGER DEFAULT 0,
        patient_accepted INTEGER DEFAULT 0,
        seen_at TEXT,
        accepted_at TEXT,
        notes TEXT,
        is_virtual INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )`,

      // Shared treatment plans sent by therapist to patient
      `CREATE TABLE IF NOT EXISTS shared_treatment_plans (
        id TEXT PRIMARY KEY,
        clinic_code TEXT NOT NULL,
        patient_external_id TEXT NOT NULL,
        patient_name TEXT,
        therapist_external_id TEXT,
        therapist_name TEXT,
        primary_diagnosis TEXT NOT NULL,
        treatment_approach TEXT,
        session_frequency TEXT,
        estimated_duration_weeks INTEGER,
        goals_json TEXT,
        status TEXT DEFAULT 'active',
        patient_seen INTEGER DEFAULT 0,
        patient_accepted INTEGER DEFAULT 0,
        seen_at TEXT,
        accepted_at TEXT,
        notes TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )`,

      // Shared chat messages table for patient <-> therapist cross-device chat
      `CREATE TABLE IF NOT EXISTS shared_messages (
        id TEXT PRIMARY KEY,
        clinic_code TEXT NOT NULL,
        sender_external_id TEXT NOT NULL,
        receiver_external_id TEXT NOT NULL,
        sender_name TEXT,
        receiver_name TEXT,
        body TEXT NOT NULL,
        is_read INTEGER DEFAULT 0,
        read_at TEXT,
        timestamp TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )`,

      // PHQ-9 clinical assessment for depression screening (hospital-grade)
      `CREATE TABLE IF NOT EXISTS phq9_assessments (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        therapist_id TEXT,
        score INTEGER NOT NULL,
        responses TEXT NOT NULL,
        severity TEXT NOT NULL,
        baseline_score INTEGER,
        is_baseline BOOLEAN DEFAULT 0,
        assessment_date DATETIME NOT NULL,
        notes TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id),
        FOREIGN KEY (therapist_id) REFERENCES users(id)
      )`,

      // Treatment response tracking (real-time outcome measurement)
      `CREATE TABLE IF NOT EXISTS treatment_responses (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        assessment_id TEXT NOT NULL,
        baseline_phq9 INTEGER,
        current_phq9 INTEGER,
        weeks_since_baseline INTEGER,
        response_percentage REAL,
        remission_status TEXT,
        individual_symptom_response TEXT,
        last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id),
        FOREIGN KEY (assessment_id) REFERENCES phq9_assessments(id)
      )`,

      // Patient engagement metrics (real-time monitoring)
      `CREATE TABLE IF NOT EXISTS engagement_metrics (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        last_check_in DATETIME,
        days_since_check_in INTEGER DEFAULT 0,
        appointment_attendance_rate REAL,
        medication_adherence_score INTEGER,
        assessment_frequency_score INTEGER,
        app_usage_hours_weekly REAL,
        message_response_time_hours REAL,
        risk_of_dropout INTEGER DEFAULT 0,
        last_assessed DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id)
      )`,

      // Clinical risk factors (real-time calculation)
      `CREATE TABLE IF NOT EXISTS clinical_risk_factors (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        severity_score REAL NOT NULL,
        risk_factors TEXT NOT NULL,
        worsening_symptoms TEXT,
        missed_appointments INTEGER DEFAULT 0,
        non_medication_adherence BOOLEAN DEFAULT 0,
        lack_of_engagement BOOLEAN DEFAULT 0,
        suicidal_ideation BOOLEAN DEFAULT 0,
        risk_level TEXT NOT NULL,
        last_calculated DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id)
      )`,

      // Automated clinical alerts (real-time monitoring)
      `CREATE TABLE IF NOT EXISTS clinical_alerts (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        therapist_id TEXT NOT NULL,
        alert_type TEXT NOT NULL,
        severity TEXT NOT NULL,
        description TEXT NOT NULL,
        triggered_metric TEXT,
        triggered_value REAL,
        threshold_value REAL,
        status TEXT DEFAULT 'active',
        acknowledged_at DATETIME,
        action_taken TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id),
        FOREIGN KEY (therapist_id) REFERENCES users(id)
      )`,

      // Evidence-based intervention recommendations
      `CREATE TABLE IF NOT EXISTS intervention_recommendations (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        therapist_id TEXT,
        recommendation_type TEXT NOT NULL,
        evidence_level TEXT NOT NULL,
        description TEXT NOT NULL,
        cbt_interventions TEXT,
        medication_suggestions TEXT,
        lifestyle_recommendations TEXT,
        follow_up_required BOOLEAN DEFAULT 1,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients(id),
        FOREIGN KEY (therapist_id) REFERENCES users(id)
      )`,

      // AI Chat messages (OpenRouter LLM integration)
      `CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        user_role TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        message TEXT NOT NULL,
        tokens_used INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )`
    ];

    for (const table of tables) {
      this.db.exec(table);
    }

    // Ensure schema updates are applied for existing databases.
    this.applyMigrations();

    // Create indexes for better query performance
    const indexes = [
      'CREATE INDEX IF NOT EXISTS idx_patients_user_id ON patients(user_id)',
      'CREATE INDEX IF NOT EXISTS idx_patients_therapist_id ON patients(therapist_id)',
      'CREATE INDEX IF NOT EXISTS idx_daily_logs_patient_id ON daily_logs(patient_id)',
      'CREATE INDEX IF NOT EXISTS idx_daily_logs_date ON daily_logs(date)',
      'CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id)',
      'CREATE INDEX IF NOT EXISTS idx_conversations_patient_id ON conversations(patient_id)',
      'CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON device_tokens(user_id)',
      'CREATE INDEX IF NOT EXISTS idx_shared_checkins_clinic_code ON shared_checkins(clinic_code)',
      'CREATE INDEX IF NOT EXISTS idx_shared_checkins_patient_external_id ON shared_checkins(patient_external_id)',
      'CREATE INDEX IF NOT EXISTS idx_shared_checkins_created_at ON shared_checkins(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_shared_appointments_clinic_code ON shared_appointments(clinic_code)',
      'CREATE INDEX IF NOT EXISTS idx_shared_appointments_patient_id ON shared_appointments(patient_external_id)',
      'CREATE INDEX IF NOT EXISTS idx_shared_appointments_scheduled_at ON shared_appointments(scheduled_at)',
      'CREATE INDEX IF NOT EXISTS idx_shared_treatment_plans_clinic_code ON shared_treatment_plans(clinic_code)',
      'CREATE INDEX IF NOT EXISTS idx_shared_treatment_plans_patient_id ON shared_treatment_plans(patient_external_id)',
      'CREATE INDEX IF NOT EXISTS idx_shared_treatment_plans_created_at ON shared_treatment_plans(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_shared_messages_clinic_code ON shared_messages(clinic_code)',
      'CREATE INDEX IF NOT EXISTS idx_shared_messages_sender_receiver ON shared_messages(sender_external_id, receiver_external_id)',
      'CREATE INDEX IF NOT EXISTS idx_phq9_patient_id ON phq9_assessments(patient_id)',
      'CREATE INDEX IF NOT EXISTS idx_phq9_assessment_date ON phq9_assessments(assessment_date)',
      'CREATE INDEX IF NOT EXISTS idx_phq9_baseline ON phq9_assessments(is_baseline)',
      'CREATE INDEX IF NOT EXISTS idx_treatment_responses_patient_id ON treatment_responses(patient_id)',
      'CREATE INDEX IF NOT EXISTS idx_engagement_metrics_patient_id ON engagement_metrics(patient_id)',
      'CREATE INDEX IF NOT EXISTS idx_clinical_risk_factors_patient_id ON clinical_risk_factors(patient_id)',
      'CREATE INDEX IF NOT EXISTS idx_clinical_alerts_patient_id ON clinical_alerts(patient_id)',
      'CREATE INDEX IF NOT EXISTS idx_clinical_alerts_therapist_id ON clinical_alerts(therapist_id)',
      'CREATE INDEX IF NOT EXISTS idx_clinical_alerts_status ON clinical_alerts(status)',
      'CREATE INDEX IF NOT EXISTS idx_intervention_recommendations_patient_id ON intervention_recommendations(patient_id)',
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_user_id ON chat_messages(user_id)',
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation_id ON chat_messages(conversation_id)',
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(created_at)',
    ];

    for (const index of indexes) {
      this.db.exec(index);
    }

    console.log('✅ All tables created successfully');
  }

  applyMigrations() {
    if (!this.db) {
      return;
    }

    // Backfill columns added after initial deployment for shared chat read receipts.
    const sharedMessagesColumns = this.db
      .prepare('PRAGMA table_info(shared_messages)')
      .all()
      .map((column) => column.name);

    if (!sharedMessagesColumns.includes('is_read')) {
      this.db.exec('ALTER TABLE shared_messages ADD COLUMN is_read INTEGER DEFAULT 0');
    }

    if (!sharedMessagesColumns.includes('read_at')) {
      this.db.exec('ALTER TABLE shared_messages ADD COLUMN read_at TEXT');
    }
  }

  getDB() {
    return this.db;
  }

  close() {
    if (this.db) {
      this.db.close();
    }
  }
}

module.exports = DatabaseService;
