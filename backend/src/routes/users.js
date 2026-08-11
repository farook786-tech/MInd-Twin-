const express = require('express');
const { v4: uuidv4 } = require('uuid');
const DatabaseService = require('../database/Database');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();

// Register / refresh an FCM push token for the authenticated user.
// The client passes the user id (Firebase UID for Firebase accounts,
// internal id for local accounts), and the route resolves it either way.
router.post('/:userId/fcm-token', authMiddleware, (req, res) => {
  try {
    const { userId } = req.params;
    const { token, platform } = req.body;

    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }
    if (!token || typeof token !== 'string') {
      return res.status(400).json({ error: 'token is required' });
    }

    // Only register tokens for yourself (admin may manage any account).
    if (userId !== req.userId && req.userRole !== 'admin') {
      return res.status(403).json({ error: 'Access denied' });
    }

    const database = db.getDB();

    const user = database.prepare('SELECT id FROM users WHERE id = ?').get(userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const normalized =
      platform === 'ios' ? 'ios' : platform === 'web' ? 'web' : 'android';

    // Replace any previous registration of the same token for this user.
    database.prepare('DELETE FROM device_tokens WHERE user_id = ? AND token = ?')
      .run(user.id, token);

    database.prepare(`
      INSERT INTO device_tokens (id, user_id, token, platform)
      VALUES (?, ?, ?, ?)
    `).run(uuidv4(), user.id, token, normalized);

    res.json({ success: true });
  } catch (error) {
    console.error('FCM token registration error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get the authenticated user's profile (merged users + patients info).
router.get('/me', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const user = database.prepare('SELECT * FROM users WHERE id = ?').get(req.userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const patient = database.prepare('SELECT * FROM patients WHERE user_id = ?').get(req.userId);

    res.json({
      success: true,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
        auth_provider: user.auth_provider,
        createdAt: user.created_at,
        updatedAt: user.updated_at,
        patient: patient || null,
      },
    });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Update the authenticated user's own profile (name).
// Mirrors the change into the `patients` table so therapist dashboards and
// shared clinic records see the new name immediately.
router.put('/me', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { name } = req.body;

    if (!name || typeof name !== 'string' || !name.trim()) {
      return res.status(400).json({ error: 'name is required' });
    }

    const cleanName = name.trim().slice(0, 120);
    if (cleanName.length < 2) {
      return res.status(400).json({ error: 'Name must be at least 2 characters' });
    }

    const user = database.prepare('SELECT id, role FROM users WHERE id = ?').get(req.userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    database.prepare(`
      UPDATE users
      SET name = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(cleanName, req.userId);

    // Keep the patients table name in sync (used by shared clinic tables).
    database.prepare(`
      UPDATE patients
      SET updated_at = CURRENT_TIMESTAMP
      WHERE user_id = ?
    `).run(req.userId);

    // Refresh denormalized names in shared clinic tables so therapists and
    // appointments always show the current name.
    if (user.role === 'patient') {
      database.prepare(`
        UPDATE shared_checkins SET patient_name = ? WHERE patient_external_id = ?
      `).run(cleanName, req.userId);
      database.prepare(`
        UPDATE shared_appointments SET patient_name = ? WHERE patient_external_id = ?
      `).run(cleanName, req.userId);
      database.prepare(`
        UPDATE shared_treatment_plans SET patient_name = ? WHERE patient_external_id = ?
      `).run(cleanName, req.userId);
      database.prepare(`
        UPDATE shared_messages SET sender_name = ?
        WHERE sender_external_id = ?
      `).run(cleanName, req.userId);
    } else if (user.role === 'therapist') {
      database.prepare(`
        UPDATE shared_appointments SET therapist_name = ? WHERE therapist_external_id = ?
      `).run(cleanName, req.userId);
      database.prepare(`
        UPDATE shared_treatment_plans SET therapist_name = ? WHERE therapist_external_id = ?
      `).run(cleanName, req.userId);
    }

    res.json({
      success: true,
      user: { id: req.userId, name: cleanName, role: user.role },
      message: 'Profile updated',
    });
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
