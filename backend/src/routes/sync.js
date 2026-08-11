const express = require('express');
const { v4: uuidv4 } = require('uuid');
const DatabaseService = require('../database/Database');
const { authMiddleware, requireRole } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();

// Returns true when the authenticated caller may write a check-in/appointment
// for the given patient external id (their own Firebase UID for patients).
const canActForPatient = (req, patientExternalId) =>
  patientExternalId === req.userId || req.userRole === 'therapist' || req.userRole === 'admin';

// Public sync endpoint for patient app check-ins using clinic code.
router.post('/public/checkin', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const {
      id: clientId,
      clinicCode,
      patientExternalId,
      patientName,
      patientEmail,
      moodScore,
      sleepHours,
      anxietyLevel,
      energyLevel,
      heartRate,
      activityLevel,
      screenTimeHours,
      riskScore,
      riskState,
      wellbeingScore,
      notes,
      interventionTitle,
      companionMessage,
      explainability,
      sourcePlatform,
    } = req.body;

    if (!clinicCode || !patientExternalId) {
      return res.status(400).json({ error: 'clinicCode and patientExternalId are required' });
    }

    if (!canActForPatient(req, patientExternalId)) {
      return res.status(403).json({ error: 'Access denied to this patient check-in' });
    }

    // Upsert on the optional client-generated id so retries and re-syncs
    // update the original check-in instead of duplicating it.
    const id = clientId || uuidv4();
    const stmt = database.prepare(`
      INSERT INTO shared_checkins (
        id, clinic_code, patient_external_id, patient_name, patient_email,
        mood_score, sleep_hours, anxiety_level, energy_level,
        heart_rate, activity_level, screen_time_hours,
        risk_score, risk_state, wellbeing_score, notes,
        intervention_title, companion_message, explainability_json, source_platform
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        clinic_code = excluded.clinic_code,
        patient_external_id = excluded.patient_external_id,
        patient_name = excluded.patient_name,
        patient_email = excluded.patient_email,
        mood_score = excluded.mood_score,
        sleep_hours = excluded.sleep_hours,
        anxiety_level = excluded.anxiety_level,
        energy_level = excluded.energy_level,
        heart_rate = excluded.heart_rate,
        activity_level = excluded.activity_level,
        screen_time_hours = excluded.screen_time_hours,
        risk_score = excluded.risk_score,
        risk_state = excluded.risk_state,
        wellbeing_score = excluded.wellbeing_score,
        notes = excluded.notes,
        intervention_title = excluded.intervention_title,
        companion_message = excluded.companion_message,
        explainability_json = excluded.explainability_json,
        source_platform = excluded.source_platform
    `);

    stmt.run(
      id,
      clinicCode,
      patientExternalId,
      patientName || 'Patient',
      patientEmail || null,
      moodScore ?? null,
      sleepHours ?? null,
      anxietyLevel ?? null,
      energyLevel ?? null,
      heartRate ?? null,
      activityLevel ?? null,
      screenTimeHours ?? null,
      riskScore ?? null,
      riskState || null,
      wellbeingScore ?? null,
      notes || null,
      interventionTitle || null,
      companionMessage || null,
      JSON.stringify(explainability || []),
      sourcePlatform || 'mobile'
    );

    res.status(201).json({
      success: true,
      id,
      message: 'Check-in synced to shared therapist dashboard',
      createdAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Public check-in sync error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Therapist dashboard fetch endpoint using shared clinic code.
router.get('/public/therapist-dashboard', authMiddleware, requireRole(['therapist', 'admin']), (req, res) => {
  try {
    const database = db.getDB();
    const clinicCode = req.query.clinicCode;
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 200);

    if (!clinicCode) {
      return res.status(400).json({ error: 'clinicCode query parameter is required' });
    }

    const entries = database.prepare(`
      SELECT * FROM shared_checkins
      WHERE clinic_code = ?
      ORDER BY created_at DESC
      LIMIT ?
    `).all(clinicCode, limit);

    const uniquePatients = new Set(entries.map((e) => e.patient_external_id));
    const emergencyCount = entries.filter((e) => (e.risk_score || 0) >= 90).length;
    const highRiskCount = entries.filter((e) => {
      const score = e.risk_score || 0;
      return score >= 70 && score < 90;
    }).length;
    const monitorCount = entries.filter((e) => {
      const score = e.risk_score || 0;
      return score >= 40 && score < 70;
    }).length;

    const avgRisk = entries.length
      ? entries.reduce((sum, e) => sum + (e.risk_score || 0), 0) / entries.length
      : 0;

    res.json({
      success: true,
      clinicCode,
      summary: {
        totalPatients: uniquePatients.size,
        emergencyCount,
        highRiskCount,
        monitorCount,
        averageRiskScore: Number(avgRisk.toFixed(2)),
        checkinCount: entries.length,
      },
      entries: entries.map((entry) => ({
        ...entry,
        explainability: (() => {
          try {
            return JSON.parse(entry.explainability_json || '[]');
          } catch (_) {
            return [];
          }
        })(),
      })),
    });
  } catch (error) {
    console.error('Therapist dashboard fetch error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.post('/public/appointments/book', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const {
      clinicCode,
      id: clientId,
      patientExternalId,
      patientName,
      therapistExternalId,
      therapistName,
      scheduledAt,
      durationMinutes,
      type,
      notes,
      isVirtual,
    } = req.body;

    if (!clinicCode || !patientExternalId || !scheduledAt) {
      return res.status(400).json({ error: 'clinicCode, patientExternalId, and scheduledAt are required' });
    }

    if (!canActForPatient(req, patientExternalId)) {
      return res.status(403).json({ error: 'Access denied to this patient appointment' });
    }

    const id = clientId || uuidv4();
    // Upsert on the (client-generated) id so re-syncing the same appointment
    // updates it instead of creating duplicates. Booking workflow fields
    // (status, patient_seen, patient_accepted) are preserved on re-send.
    const stmt = database.prepare(`
      INSERT INTO shared_appointments (
        id, clinic_code, patient_external_id, patient_name,
        therapist_external_id, therapist_name,
        scheduled_at, duration_minutes, type, status, notes, is_virtual
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        clinic_code = excluded.clinic_code,
        patient_external_id = excluded.patient_external_id,
        patient_name = excluded.patient_name,
        therapist_external_id = excluded.therapist_external_id,
        therapist_name = excluded.therapist_name,
        scheduled_at = excluded.scheduled_at,
        duration_minutes = excluded.duration_minutes,
        type = excluded.type,
        notes = excluded.notes,
        is_virtual = excluded.is_virtual
    `);

    stmt.run(
      id,
      clinicCode,
      patientExternalId,
      patientName || 'Patient',
      therapistExternalId || 'therapist_main',
      therapistName || 'Therapist',
      scheduledAt,
      durationMinutes || 50,
      type || 'followup',
      'scheduled',
      notes || null,
      isVirtual ? 1 : 0
    );

    res.status(201).json({ success: true, id, message: 'Appointment booked' });
  } catch (error) {
    console.error('Appointment booking error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get('/public/appointments', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const clinicCode = req.query.clinicCode;
    const patientExternalId = req.query.patientExternalId;

    if (!clinicCode) {
      return res.status(400).json({ error: 'clinicCode query parameter is required' });
    }

    // Patients may only view their own appointments.
    if (req.userRole === 'patient' && patientExternalId !== req.userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    let rows = [];
    if (patientExternalId) {
      rows = database.prepare(`
        SELECT * FROM shared_appointments
        WHERE clinic_code = ? AND patient_external_id = ?
        ORDER BY scheduled_at ASC
      `).all(clinicCode, patientExternalId);
    } else {
      rows = database.prepare(`
        SELECT * FROM shared_appointments
        WHERE clinic_code = ?
        ORDER BY scheduled_at ASC
      `).all(clinicCode);
    }

    res.json({ success: true, appointments: rows });
  } catch (error) {
    console.error('Fetch appointments error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.post('/public/treatment-plans/send', authMiddleware, requireRole(['therapist', 'admin']), (req, res) => {
  try {
    const database = db.getDB();
    const {
      id: clientId,
      clinicCode,
      patientExternalId,
      patientName,
      therapistExternalId,
      therapistName,
      primaryDiagnosis,
      treatmentApproach,
      sessionFrequency,
      estimatedDurationWeeks,
      goals,
      notes,
      status,
    } = req.body;

    if (!clinicCode || !patientExternalId || !primaryDiagnosis) {
      return res.status(400).json({
        error: 'clinicCode, patientExternalId, and primaryDiagnosis are required',
      });
    }

    const id = clientId || uuidv4();
    // Upsert on the (client-generated) id so re-sending the same plan updates
    // it instead of creating duplicates.
    const stmt = database.prepare(`
      INSERT INTO shared_treatment_plans (
        id, clinic_code, patient_external_id, patient_name,
        therapist_external_id, therapist_name,
        primary_diagnosis, treatment_approach, session_frequency,
        estimated_duration_weeks, goals_json, status, notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        clinic_code = excluded.clinic_code,
        patient_external_id = excluded.patient_external_id,
        patient_name = excluded.patient_name,
        therapist_external_id = excluded.therapist_external_id,
        therapist_name = excluded.therapist_name,
        primary_diagnosis = excluded.primary_diagnosis,
        treatment_approach = excluded.treatment_approach,
        session_frequency = excluded.session_frequency,
        estimated_duration_weeks = excluded.estimated_duration_weeks,
        goals_json = excluded.goals_json,
        status = excluded.status,
        notes = excluded.notes
    `);

    stmt.run(
      id,
      clinicCode,
      patientExternalId,
      patientName || 'Patient',
      therapistExternalId || 'therapist_main',
      therapistName || 'Therapist',
      primaryDiagnosis,
      treatmentApproach || null,
      sessionFrequency || null,
      estimatedDurationWeeks || null,
      JSON.stringify(Array.isArray(goals) ? goals : []),
      status || 'active',
      notes || null
    );

    res.status(201).json({ success: true, id, message: 'Treatment plan sent' });
  } catch (error) {
    console.error('Send treatment plan error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get('/public/treatment-plans', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const clinicCode = req.query.clinicCode;
    const patientExternalId = req.query.patientExternalId;

    if (!clinicCode) {
      return res.status(400).json({ error: 'clinicCode query parameter is required' });
    }

    // Patients may only view their own treatment plans.
    if (req.userRole === 'patient' && patientExternalId !== req.userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    let rows = [];
    if (patientExternalId) {
      rows = database.prepare(`
        SELECT * FROM shared_treatment_plans
        WHERE clinic_code = ? AND patient_external_id = ?
        ORDER BY created_at DESC
      `).all(clinicCode, patientExternalId);
    } else {
      rows = database.prepare(`
        SELECT * FROM shared_treatment_plans
        WHERE clinic_code = ?
        ORDER BY created_at DESC
      `).all(clinicCode);
    }

    res.json({
      success: true,
      plans: rows.map((row) => ({
        ...row,
        goals: (() => {
          try {
            return JSON.parse(row.goals_json || '[]');
          } catch (_) {
            return [];
          }
        })(),
      })),
    });
  } catch (error) {
    console.error('Fetch treatment plans error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.post('/public/chat/send', authMiddleware, async (req, res) => {
  try {
    const database = db.getDB();
    const {
      clinicCode,
      id,
      senderId,
      receiverId,
      senderName,
      receiverName,
      body,
      timestamp,
    } = req.body;

    if (!clinicCode || !senderId || !receiverId || !body) {
      return res.status(400).json({ error: 'clinicCode, senderId, receiverId, and body are required' });
    }

    // Prevent impersonation: users may only send messages as themselves.
    // (Legacy therapist-main account is allowed for therapist callers.)
    const canSendAs =
      senderId === req.userId ||
      (req.userRole === 'therapist' && senderId === 'therapist_main');
    if (!canSendAs) {
      return res.status(403).json({ error: 'Access denied: cannot send as another user' });
    }

    const messageId = id || uuidv4();
    const stmt = database.prepare(`
      INSERT OR REPLACE INTO shared_messages (
        id, clinic_code, sender_external_id, receiver_external_id,
        sender_name, receiver_name, body, timestamp
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      messageId,
      clinicCode,
      senderId,
      receiverId,
      senderName || null,
      receiverName || null,
      body,
      timestamp || new Date().toISOString()
    );

    // Fire a realtime push to the recipient so they get a notification even
    // when the app is closed or in the background.
    try {
      const NotificationService = require('../services/NotificationService');
      const notificationService = new NotificationService();
      await notificationService.sendChatMessageNotification({
        recipientUserId: receiverId,
        senderName: senderName || 'New message',
        body,
        conversationPair: [senderId, receiverId],
        senderId,
        recipientId: receiverId,
      });
    } catch (error) {
      // Notification failures must never fail the message send.
      console.warn('[Sync] Chat push notification failed:', error.message);
    }

    res.status(201).json({ success: true, id: messageId, message: 'Message synced' });
  } catch (error) {
    console.error('Shared chat send error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get('/public/chat/messages', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const clinicCode = req.query.clinicCode;
    const userA = req.query.userA;
    const userB = req.query.userB;

    if (!clinicCode || !userA || !userB) {
      return res.status(400).json({ error: 'clinicCode, userA, and userB are required' });
    }

    // Only participants (or therapists/admins) may read a conversation.
    const isParticipant =
      req.userRole === 'therapist' || req.userRole === 'admin' ||
      req.userId === userA || req.userId === userB;
    if (!isParticipant) {
      return res.status(403).json({ error: 'Access denied to this conversation' });
    }

    const rows = database.prepare(`
      SELECT * FROM shared_messages
      WHERE clinic_code = ?
        AND ((sender_external_id = ? AND receiver_external_id = ?)
          OR (sender_external_id = ? AND receiver_external_id = ?))
      ORDER BY COALESCE(timestamp, created_at) ASC
      LIMIT 300
    `).all(clinicCode, userA, userB, userB, userA);

    res.json({
      success: true,
      messages: rows.map((row) => ({
        id: row.id,
        senderId: row.sender_external_id,
        receiverId: row.receiver_external_id,
        body: row.body,
        timestamp: row.timestamp || row.created_at,
        status: 'sent',
        isRead: row.is_read ? 1 : 0,
      })),
    });
  } catch (error) {
    console.error('Shared chat fetch error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Sync patient data (from mobile app)
router.post('/patient-data', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { 
      daily_logs = [],
      crisis_alerts = [],
      messages = [],
      voice_journals = [],
      patient_profile = {},
      timestamp
    } = req.body;

    // Use transaction for atomic sync
    const transaction = database.transaction(() => {
      // Upsert patient profile
      if (patient_profile && Object.keys(patient_profile).length > 0) {
        const patient = database.prepare(`
          SELECT * FROM patients WHERE user_id = ?
        `).get(req.userId);

        if (patient) {
          database.prepare(`
            UPDATE patients
            SET risk_score = COALESCE(?, risk_score),
                wellbeing_score = COALESCE(?, wellbeing_score),
                current_risk_score = COALESCE(?, current_risk_score),
                last_check_in = COALESCE(?, last_check_in),
                updated_at = CURRENT_TIMESTAMP
            WHERE user_id = ?
          `).run(
            patient_profile.risk_score,
            patient_profile.wellbeing_score,
            patient_profile.current_risk_score,
            patient_profile.last_check_in,
            req.userId
          );
        }
      }

      // Insert daily logs
      const logStmt = database.prepare(`
        INSERT OR REPLACE INTO daily_logs
        (id, patient_id, mood_score, sleep_hours, anxiety_level, wellbeing_score, energy_level, self_report_score, notes, date, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      for (const log of daily_logs) {
        const patientId = database.prepare(
          'SELECT id FROM patients WHERE user_id = ?'
        ).get(req.userId)?.id;

        if (patientId) {
          logStmt.run(
            log.id || uuidv4(),
            patientId,
            log.mood_score,
            log.sleep_hours,
            log.anxiety_level,
            log.wellbeing_score,
            log.energy_level,
            log.self_report_score,
            log.notes,
            log.date,
            log.timestamp
          );
        }
      }

      // Insert crisis alerts
      const alertStmt = database.prepare(`
        INSERT OR REPLACE INTO crisis_alerts
        (id, patient_id, alert_type, severity, description, resolved, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `);

      for (const alert of crisis_alerts) {
        const patientId = database.prepare(
          'SELECT id FROM patients WHERE user_id = ?'
        ).get(req.userId)?.id;

        if (patientId) {
          alertStmt.run(
            alert.id || uuidv4(),
            patientId,
            alert.alert_type,
            alert.severity,
            alert.description,
            alert.resolved ? 1 : 0,
            alert.timestamp
          );
        }
      }
    });

    transaction();

    res.json({
      success: true,
      message: 'Sync completed',
      syncedAt: new Date().toISOString(),
      counts: {
        daily_logs: daily_logs.length,
        crisis_alerts: crisis_alerts.length,
        messages: messages.length
      }
    });
  } catch (error) {
    console.error('Sync error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get sync data for patient
router.get('/pull', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const since = req.query.since ? new Date(req.query.since) : new Date(Date.now() - 24 * 60 * 60 * 1000); // Default: last 24h

    const patientId = database.prepare(
      'SELECT id FROM patients WHERE user_id = ?'
    ).get(req.userId)?.id;

    if (!patientId) {
      return res.json({
        daily_logs: [],
        crisis_alerts: [],
        messages: [],
        interventions: []
      });
    }

    // Get recent data
    const daily_logs = database.prepare(`
      SELECT * FROM daily_logs 
      WHERE patient_id = ? AND timestamp > ?
      ORDER BY timestamp DESC
    `).all(patientId, since.toISOString());

    const crisis_alerts = database.prepare(`
      SELECT * FROM crisis_alerts 
      WHERE patient_id = ? AND timestamp > ?
      ORDER BY timestamp DESC
    `).all(patientId, since.toISOString());

    const interventions = database.prepare(`
      SELECT * FROM interventions 
      WHERE patient_id = ? AND timestamp > ?
      ORDER BY timestamp DESC
    `).all(patientId, since.toISOString());

    const messages = database.prepare(`
      SELECT m.* FROM messages m
      JOIN conversations c ON m.conversation_id = c.id
      WHERE c.patient_id = ? AND m.timestamp > ?
      ORDER BY m.timestamp DESC
    `).all(patientId, since.toISOString());

    res.json({
      daily_logs,
      crisis_alerts,
      interventions,
      messages,
      pulledAt: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Mark appointment as seen by patient
router.post('/public/appointments/mark-seen', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { clinicCode, appointmentId } = req.body;

    if (!clinicCode || !appointmentId) {
      return res.status(400).json({ error: 'clinicCode and appointmentId are required' });
    }

    if (req.userRole === 'patient') {
      const row = database.prepare(`
        SELECT patient_external_id FROM shared_appointments WHERE id = ?
      `).get(appointmentId);
      if (!row || row.patient_external_id !== req.userId) {
        return res.status(403).json({ error: 'Access denied to this appointment' });
      }
    }

    const now = new Date().toISOString();
    database.prepare(`
      UPDATE shared_appointments
      SET patient_seen = 1, seen_at = ?
      WHERE clinic_code = ? AND id = ?
    `).run(now, clinicCode, appointmentId);

    res.json({ success: true, message: 'Appointment marked as seen' });
  } catch (error) {
    console.error('Mark appointment seen error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Mark appointment as accepted by patient
router.post('/public/appointments/mark-accepted', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { clinicCode, appointmentId } = req.body;

    if (!clinicCode || !appointmentId) {
      return res.status(400).json({ error: 'clinicCode and appointmentId are required' });
    }

    if (req.userRole === 'patient') {
      const row = database.prepare(`
        SELECT patient_external_id FROM shared_appointments WHERE id = ?
      `).get(appointmentId);
      if (!row || row.patient_external_id !== req.userId) {
        return res.status(403).json({ error: 'Access denied to this appointment' });
      }
    }

    const now = new Date().toISOString();
    database.prepare(`
      UPDATE shared_appointments
      SET patient_accepted = 1, accepted_at = ?
      WHERE clinic_code = ? AND id = ?
    `).run(now, clinicCode, appointmentId);

    res.json({ success: true, message: 'Appointment accepted' });
  } catch (error) {
    console.error('Mark appointment accepted error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Mark treatment plan as seen by patient
router.post('/public/treatment-plans/mark-seen', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { clinicCode, planId } = req.body;

    if (!clinicCode || !planId) {
      return res.status(400).json({ error: 'clinicCode and planId are required' });
    }

    if (req.userRole === 'patient') {
      const row = database.prepare(`
        SELECT patient_external_id FROM shared_treatment_plans WHERE id = ?
      `).get(planId);
      if (!row || row.patient_external_id !== req.userId) {
        return res.status(403).json({ error: 'Access denied to this treatment plan' });
      }
    }

    const now = new Date().toISOString();
    database.prepare(`
      UPDATE shared_treatment_plans
      SET patient_seen = 1, seen_at = ?
      WHERE clinic_code = ? AND id = ?
    `).run(now, clinicCode, planId);

    res.json({ success: true, message: 'Treatment plan marked as seen' });
  } catch (error) {
    console.error('Mark treatment plan seen error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Mark treatment plan as accepted by patient
router.post('/public/treatment-plans/mark-accepted', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { clinicCode, planId } = req.body;

    if (!clinicCode || !planId) {
      return res.status(400).json({ error: 'clinicCode and planId are required' });
    }

    if (req.userRole === 'patient') {
      const row = database.prepare(`
        SELECT patient_external_id FROM shared_treatment_plans WHERE id = ?
      `).get(planId);
      if (!row || row.patient_external_id !== req.userId) {
        return res.status(403).json({ error: 'Access denied to this treatment plan' });
      }
    }

    const now = new Date().toISOString();
    database.prepare(`
      UPDATE shared_treatment_plans
      SET patient_accepted = 1, accepted_at = ?
      WHERE clinic_code = ? AND id = ?
    `).run(now, clinicCode, planId);

    res.json({ success: true, message: 'Treatment plan accepted' });
  } catch (error) {
    console.error('Mark treatment plan accepted error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Mark message as read by patient
router.post('/public/messages/mark-read', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { clinicCode, messageId } = req.body;

    if (!clinicCode || !messageId) {
      return res.status(400).json({ error: 'clinicCode and messageId are required' });
    }

    if (req.userRole === 'patient') {
      const row = database.prepare(`
        SELECT sender_external_id, receiver_external_id FROM shared_messages WHERE id = ?
      `).get(messageId);
      if (!row || (row.sender_external_id !== req.userId && row.receiver_external_id !== req.userId)) {
        return res.status(403).json({ error: 'Access denied to this message' });
      }
    }

    const now = new Date().toISOString();
    database.prepare(`
      UPDATE shared_messages
      SET is_read = 1, read_at = ?
      WHERE clinic_code = ? AND id = ?
    `).run(now, clinicCode, messageId);

    res.json({ success: true, message: 'Message marked as read' });
  } catch (error) {
    console.error('Mark message read error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
