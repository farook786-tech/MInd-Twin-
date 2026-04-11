const express = require('express');
const { v4: uuidv4 } = require('uuid');
const DatabaseService = require('../database/Database');
const { authMiddleware, requireRole } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();

// Get all patients (therapist view)
router.get('/', authMiddleware, requireRole(['therapist']), (req, res) => {
  try {
    const database = db.getDB();
    const patients = database.prepare(`
      SELECT p.*, u.name, u.email 
      FROM patients p
      JOIN users u ON p.user_id = u.id
      WHERE p.therapist_id = ?
      ORDER BY p.updated_at DESC
    `).all(req.userId);

    res.json({ patients });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get patient by ID
router.get('/:patientId', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const patient = database.prepare(`
      SELECT p.*, u.name, u.email 
      FROM patients p
      JOIN users u ON p.user_id = u.id
      WHERE p.id = ?
    `).get(req.params.patientId);

    if (!patient) {
      return res.status(404).json({ error: 'Patient not found' });
    }

    // Check authorization
    if (patient.user_id !== req.userId && patient.therapist_id !== req.userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    res.json({ patient });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update patient
router.put('/:patientId', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const patient = database.prepare('SELECT * FROM patients WHERE id = ?')
      .get(req.params.patientId);

    if (!patient) {
      return res.status(404).json({ error: 'Patient not found' });
    }

    // Only patient or their therapist can update
    if (patient.user_id !== req.userId && patient.therapist_id !== req.userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const { risk_score, wellbeing_score, current_risk_score, therapist_id } = req.body;

    const stmt = database.prepare(`
      UPDATE patients 
      SET risk_score = COALESCE(?, risk_score),
          wellbeing_score = COALESCE(?, wellbeing_score),
          current_risk_score = COALESCE(?, current_risk_score),
          therapist_id = COALESCE(?, therapist_id),
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `);

    stmt.run(risk_score, wellbeing_score, current_risk_score, therapist_id, req.params.patientId);

    const updatedPatient = database.prepare('SELECT * FROM patients WHERE id = ?')
      .get(req.params.patientId);

    res.json({ patient: updatedPatient, message: 'Patient updated' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get patient's daily logs
router.get('/:patientId/daily-logs', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const logs = database.prepare(`
      SELECT * FROM daily_logs 
      WHERE patient_id = ?
      ORDER BY timestamp DESC
      LIMIT 30
    `).all(req.params.patientId);

    res.json({ logs });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Add daily log
router.post('/:patientId/daily-logs', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { mood_score, sleep_hours, anxiety_level, wellbeing_score, notes, date } = req.body;

    const logId = uuidv4();
    const stmt = database.prepare(`
      INSERT INTO daily_logs 
      (id, patient_id, mood_score, sleep_hours, anxiety_level, wellbeing_score, energy_level, self_report_score, notes, date)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      logId,
      req.params.patientId,
      mood_score,
      sleep_hours,
      anxiety_level,
      wellbeing_score,
      wellbeing_score / 10,
      wellbeing_score,
      notes,
      date || new Date().toISOString().split('T')[0]
    );

    res.status(201).json({ id: logId, message: 'Daily log added' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get patient's crisis alerts
router.get('/:patientId/alerts', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const alerts = database.prepare(`
      SELECT * FROM crisis_alerts 
      WHERE patient_id = ?
      ORDER BY timestamp DESC
      LIMIT 20
    `).all(req.params.patientId);

    res.json({ alerts });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Add crisis alert
router.post('/:patientId/alerts', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { alert_type, severity, description } = req.body;

    const alertId = uuidv4();
    const stmt = database.prepare(`
      INSERT INTO crisis_alerts 
      (id, patient_id, alert_type, severity, description)
      VALUES (?, ?, ?, ?, ?)
    `);

    stmt.run(alertId, req.params.patientId, alert_type, severity, description);

    res.status(201).json({ id: alertId, message: 'Alert created' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
