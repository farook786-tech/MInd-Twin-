const axios = require('axios');
const DatabaseService = require('../database/Database');
const { v4: uuidv4 } = require('uuid');

/**
 * LLM Service - OpenRouter AI Integration
 * Handles AI-powered chat and clinical insights with token tracking
 * Implements rate limiting and token budget management
 */
class LLMService {
  constructor() {
    this.apiKey = process.env.OPENROUTER_API_KEY;
    this.model = process.env.OPENROUTER_MODEL || 'openai/gpt-4-turbo';
    this.baseURL = 'https://openrouter.ai/api/v1';
    this.maxTokensPerRequest = 500; // Limit per request to preserve tokens
    this.dailyTokenBudget = 10000; // Total daily token budget
  }

  /**
   * Get database instance (lazy initialization)
   */
  get db() {
    return DatabaseService.getInstance().getDB();
  }

  _getSystemPrompt(userRole = 'patient') {
    if (userRole === 'therapist') {
      return `You are a clinical support AI assistant for therapists using the MindTwin app.
Your role is to:
1. Provide patient status summaries, mood trends, and behavioral insights
2. Answer questions about specific patient data and progress
3. Suggest evidence-based interventions based on patient patterns
4. Help therapists identify concerning trends or patterns
5. Assist with clinical documentation and treatment planning

IMPORTANT:
- Maintain professional, clinical tone
- Focus on data-driven insights from patient records
- Never make definitive diagnoses - only present observations
- Keep responses concise (under 250 words)
- Reference specific patient data when available
- Always prioritize patient safety and privacy`;
    }

    // Patient role - friendly companion named "Ally"
    return `You are Ally, a warm and supportive friend helping users with their mental health journey through the MindTwin app.

Speak naturally like a caring friend would - empathetic, understanding, and encouraging. Your personality:
- Warm, genuine, and approachable
- Patient and non-judgmental
- Optimistic but realistic
- Uses casual, friendly language ("Hey", "I'm here for you", "That sounds tough")
- Shows emotional understanding and validation

Your role as a friend:
1. Listen and validate feelings without judgment
2. Share coping strategies and wellness tips in a friendly way
3. Encourage healthy habits and celebrate small wins
4. Help explore emotions and patterns together
5. Be there during difficult moments with empathy and support

IMPORTANT boundaries:
- Keep responses conversational and under 200 words
- Never diagnose or replace professional help
- If crisis signs appear (suicidal thoughts), immediately suggest crisis helpline with care
- Remind that you're here to support, but therapists are there for deeper help
- Never be preachy - be supportive and understanding

Remember: You're Ally, their supportive friend on this journey. Be real, be caring, be there for them. 💙`;
  }

  /**
   * Check daily token usage
   */
  _getDailyTokenUsage() {
    const today = new Date().toISOString().split('T')[0];
    const result = this.db.prepare(`
      SELECT SUM(tokens_used) as total FROM chat_messages 
      WHERE DATE(created_at) = ?
    `).get(today);
    
    return result.total || 0;
  }

  /**
   * Check if token budget is available
   */
  _hasTokenBudget(estimatedTokens = 200) {
    const used = this._getDailyTokenUsage();
    return (used + estimatedTokens) <= this.dailyTokenBudget;
  }

  /**
   * Send chat message and get AI response
   */
  async sendChatMessage(userId, userRole, messageText, conversationId = null, context = {}) {
    const convId = conversationId || uuidv4();

    // Handle deterministic intents first (no token usage)
    const structuredResult = this._handleStructuredIntent(userId, userRole, messageText, context);
    if (structuredResult) {
      this._storeChatMessage(userId, userRole, convId, 'user', messageText, 0);
      this._storeChatMessage(userId, userRole, convId, 'assistant', structuredResult.aiResponse, 0);

      return {
        success: true,
        conversationId: convId,
        aiResponse: structuredResult.aiResponse,
        tokensUsed: 0,
        remainingBudget: this.dailyTokenBudget - this._getDailyTokenUsage(),
        action: structuredResult.action,
      };
    }

    // Token budget check
    if (!this._hasTokenBudget(150)) {
      return {
        success: false,
        error: 'Daily token limit reached. Please try again tomorrow.',
        tokenBudget: this._getDailyTokenUsage() + '/' + this.dailyTokenBudget
      };
    }

    try {
      // Get conversation history (last 5 messages for context)
      const history = conversationId 
        ? this._getConversationHistory(conversationId, 5)
        : [];

      // Build messages array for OpenRouter
      const messages = [
        {
          role: 'system',
          content: this._getSystemPrompt(userRole),
        },
        ...history.map(msg => ({
          role: msg.role,
          content: msg.message
        })),
        {
          role: 'user',
          content: messageText
        }
      ];

      // Call OpenRouter API
      const response = await axios.post(`${this.baseURL}/chat/completions`, {
        model: this.model,
        messages,
        max_tokens: this.maxTokensPerRequest,
        temperature: 0.7
      }, {
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'HTTP-Referer': 'http://localhost:5000'
        }
      });

      const aiMessage = response.data.choices[0].message.content;
      const tokensUsed = response.data.usage.total_tokens || 0;

      // Store messages in database
      this._storeChatMessage(userId, userRole, convId, 'user', messageText, tokensUsed / 2);
      this._storeChatMessage(userId, userRole, convId, 'assistant', aiMessage, tokensUsed / 2);

      return {
        success: true,
        conversationId: convId,
        aiResponse: aiMessage,
        tokensUsed,
        remainingBudget: this.dailyTokenBudget - (this._getDailyTokenUsage() + tokensUsed)
      };
    } catch (error) {
      console.error('LLM API Error:', error.message);
      return {
        success: false,
        error: 'Failed to get AI response: ' + error.message
      };
    }
  }

  /**
   * Store chat message in database
   */
  _storeChatMessage(userId, userRole, conversationId, role, message, tokensUsed = 0) {
    try {
      this.db.prepare(`
        INSERT INTO chat_messages (
          id, user_id, user_role, conversation_id, role, message, tokens_used, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
      `).run(
        uuidv4(),
        userId,
        userRole,
        conversationId,
        role,
        message,
        Math.ceil(tokensUsed)
      );
    } catch (error) {
      console.error('Error storing chat message:', error);
    }
  }

  /**
   * Get conversation history
   */
  _getConversationHistory(conversationId, limit = 10) {
    return this.db.prepare(`
      SELECT role, message FROM chat_messages 
      WHERE conversation_id = ? 
      ORDER BY created_at DESC 
      LIMIT ?
    `).all(conversationId, limit).reverse();
  }

  /**
   * Get full conversation (for frontend)
   */
  getConversation(conversationId) {
    return this.db.prepare(`
      SELECT id, role, message, created_at 
      FROM chat_messages 
      WHERE conversation_id = ? 
      ORDER BY created_at ASC
    `).all(conversationId);
  }

  /**
   * Get all conversations for a user
   */
  getUserConversations(userId) {
    return this.db.prepare(`
      SELECT DISTINCT 
        cm.conversation_id as conversation_id,
        (SELECT message FROM chat_messages WHERE conversation_id = cm.conversation_id ORDER BY created_at ASC LIMIT 1) as first_message,
        (SELECT created_at FROM chat_messages WHERE conversation_id = cm.conversation_id ORDER BY created_at DESC LIMIT 1) as last_message,
        COUNT(*) as message_count
      FROM chat_messages cm
      WHERE cm.user_id = ?
      GROUP BY cm.conversation_id
      ORDER BY last_message DESC
    `).all(userId);
  }

  _handleStructuredIntent(userId, userRole, messageText, context = {}) {
    const text = (messageText || '').toLowerCase();

    const bookingIntent =
      /(book|schedule|reserve).*(appointment|session)/.test(text) ||
      /(appointment|session).*(book|schedule|reserve)/.test(text);

    const rateIntent =
      /(mental health|wellbeing|well-being|mood|score|rate).*(today|yesterday|week)/.test(text) ||
      /(today|yesterday|this week|week).*(mental health|wellbeing|well-being|mood|score|rate)/.test(text);

    const therapistDetailsIntent =
      userRole === 'therapist' &&
      (/(patient|this patient).*(detail|status|health|state|rate|score)/.test(text) ||
        /(today|yesterday|week).*(health|status|state|mood|wellbeing|score)/.test(text));

    if (bookingIntent) {
      return this._handleBookingIntent(userId, userRole, messageText, context);
    }

    if (therapistDetailsIntent) {
      return this._handleTherapistPatientStatusIntent(userId, messageText, context);
    }

    if (rateIntent) {
      return this._handleMentalRateIntent(userId, userRole, messageText, context);
    }

    return null;
  }

  _resolvePatientId(userId, userRole, context = {}, messageText = '') {
    if (userRole === 'therapist') {
      const contextPatientId = context?.targetPatientId;
      if (contextPatientId) {
        const direct = this.db.prepare('SELECT id FROM patients WHERE id = ? LIMIT 1').get(contextPatientId);
        if (direct?.id) return direct.id;

        const byUser = this.db.prepare('SELECT id FROM patients WHERE user_id = ? LIMIT 1').get(contextPatientId);
        if (byUser?.id) return byUser.id;
      }

      const uuidMatch = (messageText || '').match(/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i);
      if (uuidMatch?.[0]) {
        const byId = this.db.prepare('SELECT id FROM patients WHERE id = ? OR user_id = ? LIMIT 1').get(uuidMatch[0], uuidMatch[0]);
        if (byId?.id) return byId.id;
      }

      return null;
    }

    if (userRole === 'patient') {
      const byPatientId = this.db.prepare(
        'SELECT id FROM patients WHERE id = ? LIMIT 1'
      ).get(userId);
      if (byPatientId?.id) return byPatientId.id;

      const byUserId = this.db.prepare(
        'SELECT id FROM patients WHERE user_id = ? LIMIT 1'
      ).get(userId);
      if (byUserId?.id) return byUserId.id;
    }

    return null;
  }

  _resolvePatientName(patientId) {
    if (!patientId) return 'Patient';

    const row = this.db.prepare(`
      SELECT u.name as name
      FROM patients p
      LEFT JOIN users u ON u.id = p.user_id
      WHERE p.id = ?
      LIMIT 1
    `).get(patientId);

    return row?.name || 'Patient';
  }

  _parseRequestedPeriod(text) {
    if (text.includes('yesterday')) return 'yesterday';
    if (text.includes('week')) return 'week';
    return 'today';
  }

  _dateRangeForPeriod(period) {
    const now = new Date();
    const end = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const start = new Date(end);

    if (period === 'yesterday') {
      start.setDate(start.getDate() - 1);
      end.setDate(end.getDate() - 1);
    } else if (period === 'week') {
      start.setDate(start.getDate() - 6);
    }

    const toSqlDate = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    return { startDate: toSqlDate(start), endDate: toSqlDate(end) };
  }

  _handleMentalRateIntent(userId, userRole, messageText, context = {}) {
    const patientId = this._resolvePatientId(userId, userRole, context, messageText);
    if (!patientId) {
      return {
        action: 'mental_rate_unavailable',
        aiResponse: 'I can show mental health rates only for a patient account linked to daily check-ins. Please open chat from your patient app account.',
      };
    }

    const period = this._parseRequestedPeriod(messageText.toLowerCase());
    const { startDate, endDate } = this._dateRangeForPeriod(period);

    const row = this.db.prepare(`
      SELECT
        COUNT(*) as entry_count,
        AVG(wellbeing_score) as avg_wellbeing,
        AVG(mood_score) as avg_mood,
        AVG(anxiety_level) as avg_anxiety,
        AVG(sleep_hours) as avg_sleep
      FROM daily_logs
      WHERE patient_id = ?
        AND DATE(COALESCE(date, timestamp)) BETWEEN DATE(?) AND DATE(?)
    `).get(patientId, startDate, endDate);

    const entryCount = Number(row?.entry_count || 0);
    const label = period === 'yesterday' ? 'yesterday' : period === 'week' ? 'this week' : 'today';

    if (entryCount === 0) {
      return {
        action: 'mental_rate_not_found',
        aiResponse: `I could not find check-in data for ${label}. Please complete a daily check-in first.`,
      };
    }

    const wellbeing = Number(row.avg_wellbeing || 0).toFixed(1);
    const mood = Number(row.avg_mood || 0).toFixed(1);
    const anxiety = Number(row.avg_anxiety || 0).toFixed(1);
    const sleep = Number(row.avg_sleep || 0).toFixed(1);

    return {
      action: 'mental_rate_summary',
      aiResponse:
        `Your mental health summary for ${label}: ` +
        `wellbeing ${wellbeing}/100, mood ${mood}/10, anxiety ${anxiety}/10, sleep ${sleep} hours (from ${entryCount} check-in${entryCount > 1 ? 's' : ''}).`,
    };
  }

  _parseAppointmentDateTime(text) {
    const now = new Date();
    const target = new Date(now.getTime());
    target.setDate(target.getDate() + 1);
    target.setHours(10, 0, 0, 0);

    if (text.includes('today')) {
      target.setDate(now.getDate());
    } else if (text.includes('tomorrow')) {
      target.setDate(now.getDate() + 1);
    }

    const weekdayMap = {
      sunday: 0,
      monday: 1,
      tuesday: 2,
      wednesday: 3,
      thursday: 4,
      friday: 5,
      saturday: 6,
    };

    for (const [name, dayNum] of Object.entries(weekdayMap)) {
      if (text.includes(name)) {
        const current = now.getDay();
        let diff = (dayNum - current + 7) % 7;
        if (diff === 0) diff = 7;
        target.setDate(now.getDate() + diff);
        break;
      }
    }

    const timeMatch = text.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
    if (timeMatch) {
      let hours = parseInt(timeMatch[1], 10);
      const minutes = parseInt(timeMatch[2] || '0', 10);
      const meridian = (timeMatch[3] || '').toLowerCase();

      if (meridian === 'pm' && hours < 12) hours += 12;
      if (meridian === 'am' && hours === 12) hours = 0;

      if (!Number.isNaN(hours) && !Number.isNaN(minutes)) {
        target.setHours(hours, minutes, 0, 0);
      }
    }

    return target;
  }

  _toSqlDateTime(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    const ss = '00';
    return `${y}-${m}-${day} ${hh}:${mm}:${ss}`;
  }

  _formatHumanDateTime(d) {
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    let h = d.getHours();
    const m = String(d.getMinutes()).padStart(2, '0');
    const meridian = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h === 0) h = 12;
    return `${weekdays[d.getDay()]}, ${months[d.getMonth()]} ${d.getDate()} at ${h}:${m} ${meridian}`;
  }

  _handleBookingIntent(userId, userRole, messageText, context = {}) {
    const patientId = this._resolvePatientId(userId, userRole, context, messageText);
    if (!patientId) {
      return {
        action: 'appointment_booking_unavailable',
        aiResponse: 'I can only book appointments from a patient account linked to this app. Please try from the patient profile chat.',
      };
    }

    const patientName = this._resolvePatientName(patientId);
    const requested = this._parseAppointmentDateTime(messageText.toLowerCase());
    const scheduledAt = this._toSqlDateTime(requested);
    const clinicCode = process.env.DEFAULT_CLINIC_CODE || 'DEMO_CLINIC_001';
    const appointmentId = uuidv4();

    this.db.prepare(`
      INSERT INTO shared_appointments (
        id,
        clinic_code,
        patient_external_id,
        patient_name,
        scheduled_at,
        duration_minutes,
        type,
        status,
        notes,
        is_virtual,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    `).run(
      appointmentId,
      clinicCode,
      patientId,
      patientName,
      scheduledAt,
      50,
      'followup',
      'scheduled',
      `Booked from AI chat: ${messageText}`,
      1
    );

    return {
      action: 'appointment_booked',
      aiResponse: `Your appointment is booked for ${this._formatHumanDateTime(requested)}. I saved it to your schedule.`,
    };
  }

  _handleTherapistPatientStatusIntent(therapistUserId, messageText, context = {}) {
    const patientId = this._resolvePatientId(therapistUserId, 'therapist', context, messageText);
    if (!patientId) {
      return {
        action: 'therapist_patient_missing',
        aiResponse: 'I could not identify which patient you mean. Please open this chat from a specific patient profile.',
      };
    }

    const profile = this.db.prepare(`
      SELECT
        p.id,
        p.age,
        p.risk_score,
        p.current_risk_score,
        p.wellbeing_score,
        p.last_check_in,
        u.name,
        u.email
      FROM patients p
      LEFT JOIN users u ON u.id = p.user_id
      WHERE p.id = ?
      LIMIT 1
    `).get(patientId);

    if (!profile) {
      return {
        action: 'therapist_patient_not_found',
        aiResponse: 'Patient profile not found in the database.',
      };
    }

    const today = this._dateRangeForPeriod('today');
    const week = this._dateRangeForPeriod('week');

    const todayStats = this.db.prepare(`
      SELECT
        COUNT(*) as entry_count,
        AVG(wellbeing_score) as wellbeing,
        AVG(mood_score) as mood,
        AVG(anxiety_level) as anxiety,
        AVG(sleep_hours) as sleep
      FROM daily_logs
      WHERE patient_id = ?
        AND DATE(COALESCE(date, timestamp)) BETWEEN DATE(?) AND DATE(?)
    `).get(patientId, today.startDate, today.endDate);

    const weekStats = this.db.prepare(`
      SELECT
        COUNT(*) as entry_count,
        AVG(wellbeing_score) as wellbeing,
        AVG(mood_score) as mood,
        AVG(anxiety_level) as anxiety,
        AVG(sleep_hours) as sleep
      FROM daily_logs
      WHERE patient_id = ?
        AND DATE(COALESCE(date, timestamp)) BETWEEN DATE(?) AND DATE(?)
    `).get(patientId, week.startDate, week.endDate);

    const latest = this.db.prepare(`
      SELECT
        DATE(COALESCE(date, timestamp)) as log_date,
        wellbeing_score,
        mood_score,
        anxiety_level,
        sleep_hours,
        self_report_score,
        notes,
        timestamp
      FROM daily_logs
      WHERE patient_id = ?
      ORDER BY DATETIME(COALESCE(timestamp, created_at)) DESC
      LIMIT 1
    `).get(patientId);

    const todayCount = Number(todayStats?.entry_count || 0);
    const weekCount = Number(weekStats?.entry_count || 0);

    const fmt = (v, digits = 1) => (v === null || v === undefined ? 'N/A' : Number(v).toFixed(digits));
    const riskPct = Math.round(Number(profile.current_risk_score || profile.risk_score || 0) * 100);

    const latestBlock = latest
      ? `Latest check-in (${latest.log_date || 'unknown date'}): wellbeing ${fmt(latest.wellbeing_score)}/100, mood ${fmt(latest.mood_score)}/10, anxiety ${fmt(latest.anxiety_level)}/10, sleep ${fmt(latest.sleep_hours)}h.`
      : 'No latest check-in found.';

    return {
      action: 'therapist_patient_status',
      aiResponse:
        `Patient details: ${profile.name || 'Unknown'} (ID ${profile.id}), age ${profile.age ?? 'N/A'}, baseline wellbeing ${fmt(profile.wellbeing_score)}/100, current risk ${riskPct}%. ` +
        `Today: ${todayCount > 0 ? `wellbeing ${fmt(todayStats.wellbeing)}/100, mood ${fmt(todayStats.mood)}/10, anxiety ${fmt(todayStats.anxiety)}/10, sleep ${fmt(todayStats.sleep)}h (${todayCount} check-in${todayCount > 1 ? 's' : ''})` : 'no check-in yet'}. ` +
        `This week: ${weekCount > 0 ? `wellbeing ${fmt(weekStats.wellbeing)}/100, mood ${fmt(weekStats.mood)}/10, anxiety ${fmt(weekStats.anxiety)}/10, sleep ${fmt(weekStats.sleep)}h (${weekCount} check-ins)` : 'no check-ins yet'}. ` +
        `${latestBlock}`,
    };
  }

  /**
   * Generate crisis intervention prompt (minimal tokens)
   */
  async generateCrisisResponse(patientId, riskLevel) {
    if (!this._hasTokenBudget(100)) {
      return { error: 'Token budget low' };
    }

    try {
      const crisisPrompt = `
Patient risk level: ${riskLevel}
Provide brief, compassionate crisis support (max 100 words).
Include: validation, grounding technique, safety resources.`;

      const response = await axios.post(`${this.baseURL}/chat/completions`, {
        model: this.model,
        messages: [
          { role: 'system', content: this.systemPrompt },
          { role: 'user', content: crisisPrompt }
        ],
        max_tokens: 150,
        temperature: 0.8
      }, {
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'HTTP-Referer': 'http://localhost:5000'
        }
      });

      return {
        crisisMessage: response.data.choices[0].message.content,
        tokensUsed: response.data.usage.total_tokens
      };
    } catch (error) {
      console.error('Crisis response error:', error);
      return {
        crisisMessage: 'Please reach out to a crisis helpline: National Suicide Prevention Lifeline: 988'
      };
    }
  }

  /**
   * Analyze patient assessment with AI (strategic token use)
   */
  async analyzeAssessment(assessmentData) {
    if (!this._hasTokenBudget(200)) {
      return { error: 'Token budget low' };
    }

    try {
      const analysis = `Summary of assessment - PHQ-9: ${assessmentData.phq9_score}, Risk: ${assessmentData.risk_level}. Provide brief clinical insights (max 100 words).`;

      const response = await axios.post(`${this.baseURL}/chat/completions`, {
        model: this.model,
        messages: [
          { role: 'system', content: 'You are a clinical mental health AI. Provide concise analysis.' },
          { role: 'user', content: analysis }
        ],
        max_tokens: 150,
        temperature: 0.7
      }, {
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'HTTP-Referer': 'http://localhost:5000'
        }
      });

      return {
        insight: response.data.choices[0].message.content,
        tokensUsed: response.data.usage.total_tokens
      };
    } catch (error) {
      console.error('Assessment analysis error:', error);
      return { insight: 'Assessment recorded successfully.' };
    }
  }

  /**
   * Get token budget status
   */
  getTokenStatus() {
    const used = this._getDailyTokenUsage();
    return {
      dailyUsed: used,
      dailyBudget: this.dailyTokenBudget,
      remaining: this.dailyTokenBudget - used,
      percentageUsed: Math.round((used / this.dailyTokenBudget) * 100)
    };
  }
}

module.exports = LLMService;
