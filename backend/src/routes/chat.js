const express = require('express');
const router = express.Router();
const LLMService = require('../services/LLMService');
const { authMiddleware, canAccessPatient } = require('../middleware/auth');

const llm = new LLMService();

/**
 * POST /api/chat/message
 * Send a message and get AI response
 */
router.post('/message', authMiddleware, async (req, res) => {
  try {
    const { userId, userRole, message, conversationId, context } = req.body;

    if (!userId || !userRole || !message) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: userId, userRole, message'
      });
    }

    // Patients may only chat on their own behalf.
    if (req.userRole === 'patient' && userId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    const result = await llm.sendChatMessage(userId, userRole, message, conversationId, context || {});

    if (!result.success) {
      return res.status(429).json(result); // 429 Too Many Requests
    }

    res.json(result);
  } catch (error) {
    console.error('Chat message error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to process chat message'
    });
  }
});

/**
 * GET /api/chat/conversation/:conversationId
 * Retrieve chat conversation history
 */
router.get('/conversation/:conversationId', authMiddleware, (req, res) => {
  try {
    const { conversationId } = req.params;
    const messages = llm.getConversation(conversationId);

    res.json({
      success: true,
      conversationId,
      messages
    });
  } catch (error) {
    console.error('Get conversation error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve conversation'
    });
  }
});

/**
 * GET /api/chat/conversations/:userId
 * Get all conversations for a user
 */
router.get('/conversations/:userId', authMiddleware, (req, res) => {
  try {
    const { userId } = req.params;

    // Patients may only list their own conversations.
    if (req.userRole === 'patient' && userId !== req.userId) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    const conversations = llm.getUserConversations(userId);

    res.json({
      success: true,
      userId,
      conversations: conversations || []
    });
  } catch (error) {
    console.error('Get conversations error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve conversations'
    });
  }
});

/**
 * GET /api/chat/tokens/status
 * Get current token usage status
 */
router.get('/tokens/status', authMiddleware, (req, res) => {
  try {
    const status = llm.getTokenStatus();
    res.json({
      success: true,
      tokenStatus: status
    });
  } catch (error) {
    console.error('Token status error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get token status'
    });
  }
});

/**
 * POST /api/chat/crisis-response
 * Generate crisis intervention message (minimal token use)
 */
router.post('/crisis-response', authMiddleware, async (req, res) => {
  try {
    const { patientId, riskLevel } = req.body;

    if (!patientId || !riskLevel) {
      return res.status(400).json({
        success: false,
        error: 'Missing patientId or riskLevel'
      });
    }

    if (!canAccessPatient(req, patientId)) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    const result = await llm.generateCrisisResponse(patientId, riskLevel);

    if (result.error) {
      return res.status(429).json(result);
    }

    res.json(result);
  } catch (error) {
    console.error('Crisis response error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate crisis response'
    });
  }
});

/**
 * POST /api/chat/analyze-assessment
 * Analyze patient assessment with AI
 */
router.post('/analyze-assessment', authMiddleware, async (req, res) => {
  try {
    const { assessmentData } = req.body;

    if (!assessmentData) {
      return res.status(400).json({
        success: false,
        error: 'Missing assessment data'
      });
    }

    const result = await llm.analyzeAssessment(assessmentData);

    if (result.error) {
      return res.status(429).json(result);
    }

    res.json(result);
  } catch (error) {
    console.error('Assessment analysis error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to analyze assessment'
    });
  }
});

module.exports = router;
