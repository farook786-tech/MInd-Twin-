const express = require('express');
const DatabaseService = require('../database/Database');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();

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
