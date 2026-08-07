const express = require('express');
const { v4: uuidv4 } = require('uuid');
const DatabaseService = require('../database/Database');
const NotificationService = require('../services/NotificationService');
const { authMiddleware, requirePatientAccess } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();
const notificationService = new NotificationService();

// POST /api/alerts/sos
// Patient-triggered SOS. Creates a crisis alert and notifies the patient's
// assigned therapist in real time.
router.post('/sos', authMiddleware, requirePatientAccess, async (req, res) => {
  try {
    const { patientId, description } = req.body;

    if (!patientId) {
      return res.status(400).json({ error: 'patientId required' });
    }

    const database = db.getDB();
    const patient = database.prepare(
      'SELECT id, user_id, therapist_id FROM patients WHERE user_id = ? OR id = ?',
    ).get(patientId, patientId);

    if (!patient) {
      return res.status(404).json({ error: 'Patient not found' });
    }

    const alertId = uuidv4();
    const message = description || 'Patient triggered an SOS alert from the app.';
    database.prepare(`
      INSERT INTO crisis_alerts (id, patient_id, alert_type, severity, description)
      VALUES (?, ?, 'sos', 1.0, ?)
    `).run(alertId, patient.id, message);

    if (patient.therapist_id) {
      let patientName = patientId;
      try {
        const user = database.prepare('SELECT name FROM users WHERE id = ?').get(patient.user_id);
        if (user && user.name) patientName = user.name;
      } catch (_) {}

      notificationService.sendClinicalAlertNotification(
        patient.therapist_id,
        patientName,
        'sos',
        'critical',
        message,
        1,
        1,
      );
    }

    res.status(201).json({
      success: true,
      id: alertId,
      message: 'SOS alert sent to your therapist',
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get alerts for current user (therapist or patient)
router.get('/', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    
    // Get alerts for therapist's patients or patient's own alerts
    const alerts = database.prepare(`
      SELECT ca.*, p.user_id, u.name
      FROM crisis_alerts ca
      JOIN patients p ON ca.patient_id = p.id
      JOIN users u ON p.user_id = u.id
      WHERE p.therapist_id = ? OR p.user_id = ?
      ORDER BY ca.timestamp DESC
      LIMIT 50
    `).all(req.userId, req.userId);

    res.json({ alerts });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get alert by ID
router.get('/:alertId', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const alert = database.prepare(`
      SELECT ca.* FROM crisis_alerts ca
      WHERE ca.id = ?
    `).get(req.params.alertId);

    if (!alert) {
      return res.status(404).json({ error: 'Alert not found' });
    }

    res.json({ alert });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update alert status
router.patch('/:alertId', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { resolved, severity, description } = req.body;

    const updateStmt = database.prepare(`
      UPDATE crisis_alerts
      SET resolved = COALESCE(?, resolved),
          severity = COALESCE(?, severity),
          description = COALESCE(?, description),
          resolved_at = CASE WHEN ? = 1 THEN CURRENT_TIMESTAMP ELSE resolved_at END
      WHERE id = ?
    `);

    updateStmt.run(resolved, severity, description, resolved, req.params.alertId);

    const alert = database.prepare('SELECT * FROM crisis_alerts WHERE id = ?')
      .get(req.params.alertId);

    res.json({ alert, message: 'Alert updated' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
