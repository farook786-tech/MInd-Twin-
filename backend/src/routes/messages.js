const express = require('express');
const { v4: uuidv4 } = require('uuid');
const DatabaseService = require('../database/Database');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();

// Get conversations for current user
router.get('/conversations', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const conversations = database.prepare(`
      SELECT c.*, p.user_id as patient_user_id, u.name as other_user_name
      FROM conversations c
      LEFT JOIN patients p ON c.patient_id = p.id
      LEFT JOIN users u ON CASE 
        WHEN c.therapist_id = ? THEN p.user_id = u.id
        ELSE c.therapist_id = u.id
      END
      WHERE c.patient_id IN (
        SELECT id FROM patients WHERE user_id = ?
      ) OR c.therapist_id = ?
      ORDER BY c.last_message_at DESC
    `).all(req.userId, req.userId, req.userId);

    res.json({ conversations });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get messages for a conversation
router.get('/conversations/:conversationId', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const messages = database.prepare(`
      SELECT m.*, u.name as sender_name
      FROM messages m
      LEFT JOIN users u ON m.sender_id = u.id
      WHERE m.conversation_id = ?
      ORDER BY m.timestamp ASC
      LIMIT 100
    `).all(req.params.conversationId);

    res.json({ messages });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Send message
router.post('/conversations/:conversationId/messages', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { content, message_type = 'text' } = req.body;

    if (!content) {
      return res.status(400).json({ error: 'Content required' });
    }

    const messageId = uuidv4();
    const stmt = database.prepare(`
      INSERT INTO messages 
      (id, conversation_id, sender_id, content, message_type)
      VALUES (?, ?, ?, ?, ?)
    `);

    stmt.run(messageId, req.params.conversationId, req.userId, content, message_type);

    // Update last_message_at
    const updateStmt = database.prepare(`
      UPDATE conversations
      SET last_message_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `);
    updateStmt.run(req.params.conversationId);

    res.status(201).json({ 
      id: messageId, 
      message: 'Message sent',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create or get conversation
router.post('/conversations', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const { patient_id, therapist_id, title } = req.body;

    // Check if conversation already exists
    const existing = database.prepare(`
      SELECT * FROM conversations
      WHERE patient_id = ? AND therapist_id = ?
    `).get(patient_id, therapist_id);

    if (existing) {
      return res.json({ conversation: existing });
    }

    // Create new conversation
    const conversationId = uuidv4();
    const stmt = database.prepare(`
      INSERT INTO conversations 
      (id, patient_id, therapist_id, title)
      VALUES (?, ?, ?, ?)
    `);

    stmt.run(conversationId, patient_id, therapist_id, title || 'New Conversation');

    const conversation = database.prepare('SELECT * FROM conversations WHERE id = ?')
      .get(conversationId);

    res.status(201).json({ conversation, message: 'Conversation created' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
