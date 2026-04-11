const express = require('express');
const DatabaseService = require('../database/Database');
const { authMiddleware, requireRole } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();

// Get therapist dashboard
router.get('/dashboard', authMiddleware, requireRole(['therapist']), (req, res) => {
  try {
    const database = db.getDB();

    // Get all patients assigned to this therapist
    const patients = database.prepare(`
      SELECT p.id, p.user_id, u.name, p.risk_score, p.wellbeing_score, p.last_check_in
      FROM patients p
      JOIN users u ON p.user_id = u.id
      WHERE p.therapist_id = ?
    `).all(req.userId);

    // Get pending alerts
    const pendingAlerts = database.prepare(`
      SELECT ca.*, p.id as patient_id, u.name as patient_name
      FROM crisis_alerts ca
      JOIN patients p ON ca.patient_id = p.id
      JOIN users u ON p.user_id = u.id
      WHERE p.therapist_id = ? AND ca.resolved = 0
      ORDER BY ca.timestamp DESC
      LIMIT 10
    `).all(req.userId);

    // Get recent interventions
    const recentInterventions = database.prepare(`
      SELECT i.*, p.id as patient_id, u.name as patient_name
      FROM interventions i
      JOIN patients p ON i.patient_id = p.id
      JOIN users u ON p.user_id = u.id
      WHERE p.therapist_id = ?
      ORDER BY i.timestamp DESC
      LIMIT 5
    `).all(req.userId);

    res.json({
      patientCount: patients.length,
      patients,
      pendingAlerts,
      recentInterventions,
      highRiskCount: patients.filter(p => p.risk_score > 0.7).length,
      stableCount: patients.filter(p => p.risk_score <= 0.3).length
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Resolve alert
router.put('/alerts/:alertId/resolve', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    
    const stmt = database.prepare(`
      UPDATE crisis_alerts 
      SET resolved = 1, resolved_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `);

    stmt.run(req.params.alertId);

    res.json({ message: 'Alert resolved' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create intervention
router.post('/interventions', authMiddleware, requireRole(['therapist']), (req, res) => {
  try {
    const database = db.getDB();
    const { patient_id, intervention_type, description } = req.body;
    const { v4: uuidv4 } = require('uuid');

    const interventionId = uuidv4();
    const stmt = database.prepare(`
      INSERT INTO interventions 
      (id, patient_id, therapist_id, intervention_type, description)
      VALUES (?, ?, ?, ?, ?)
    `);

    stmt.run(interventionId, patient_id, req.userId, intervention_type, description);

    res.status(201).json({ id: interventionId, message: 'Intervention created' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
