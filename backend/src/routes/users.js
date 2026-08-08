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

module.exports = router;
