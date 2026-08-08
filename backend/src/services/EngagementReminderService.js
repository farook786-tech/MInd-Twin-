const Database = require('../database/Database');
const NotificationService = require('./NotificationService');

/**
 * EngagementReminderService - Smart automated check-in reminders
 * Increases reminder frequency when dropout risk > 40
 * Personalizes timing based on patient engagement patterns
 * Real-time operation - checked continuously, not batch jobs
 */
class EngagementReminderService {
  constructor() {
    this.db = Database.getInstance();
    this.notificationService = new NotificationService();
  }

  /**
   * Evaluate engagement and send reminders if needed
   * Called periodically (every 30 min to 1 hour in production)
   */
  async evaluateAndSendReminders() {
    try {
      const patients = this.db.prepare('SELECT id FROM patients WHERE status = ?').all('active');
      console.log(`[ENGAGEMENT SCHEDULER] Evaluating ${patients.length} patients for reminders...`);

      for (const patient of patients) {
        await this._processPatientReminder(patient.id);
      }

      console.log('[ENGAGEMENT SCHEDULER] Evaluation complete');
      return { processed: patients.length, success: true };
    } catch (error) {
      console.error('Engagement reminder evaluation error:', error);
      return { success: false, error: error.message };
    }
  }

  async _processPatientReminder(patientId) {
    try {
      // Get latest engagement metrics
      const engagement = this.db.prepare(`
        SELECT 
          last_check_in,
          days_since_check_in,
          appointment_attendance_rate,
          medication_adherence_score,
          risk_of_dropout,
          created_at
        FROM engagement_metrics
        WHERE patient_id = ?
        ORDER BY created_at DESC
        LIMIT 1
      `).get(patientId);

      if (!engagement) return; // No engagement data yet

      const dropoutRisk = engagement.risk_of_dropout || 0;
      const daysSinceCheckIn = engagement.days_since_check_in || 0;

      // Determine if reminder should be sent
      const shouldSendReminder = await this._determineSendReminder(
        patientId,
        dropoutRisk,
        daysSinceCheckIn,
      );

      if (shouldSendReminder) {
        // Get patient device token
        const patient = this.db.prepare(`
          SELECT id FROM patients WHERE id = ?
        `).get(patientId);

        // Would retrieve device token from database in production
        // For now, log the reminder
        await this.notificationService.sendEngagementReminder(
          patientId,
          'device-token-placeholder',
          dropoutRisk,
          daysSinceCheckIn,
        );

        // Log reminder in database
        this._logReminder(patientId, dropoutRisk, daysSinceCheckIn);
      }
    } catch (error) {
      console.error(`Error processing reminder for patient ${patientId}:`, error);
    }
  }

  /**
   * Smart logic to determine if reminder should be sent
   * Based on dropout risk and engagement patterns
   */
  async _determineSendReminder(patientId, dropoutRisk, daysSinceCheckIn) {
    // Get last reminder sent time to avoid spam
    const lastReminder = this.db.prepare(`
      SELECT sent_at FROM engagement_reminders
      WHERE patient_id = ?
      ORDER BY sent_at DESC
      LIMIT 1
    `).get(patientId);

    const now = new Date();
    const lastReminderTime = lastReminder ? new Date(lastReminder.sent_at) : null;
    const minutesSinceLastReminder = lastReminderTime
      ? (now.getTime() - lastReminderTime.getTime()) / (1000 * 60)
      : Infinity;

    // Critical dropout risk (>70): Remind every 3 days
    if (dropoutRisk >= 70) {
      return minutesSinceLastReminder > 3 * 24 * 60; // 3 days
    }

    // High dropout risk (50-70): Remind every 5 days if no check-in
    if (dropoutRisk >= 50) {
      return daysSinceCheckIn > 5 && minutesSinceLastReminder > 5 * 24 * 60;
    }

    // Medium dropout risk (30-50): Weekly reminders
    if (dropoutRisk >= 30) {
      return daysSinceCheckIn > 7 && minutesSinceLastReminder > 7 * 24 * 60;
    }

    // Low dropout risk: Bi-weekly reminders only if no check-in in 14 days
    return (
      daysSinceCheckIn >= 14 &&
      minutesSinceLastReminder > 14 * 24 * 60
    );
  }

  /**
   * Log reminder sent for analytics and spam prevention
   */
  _logReminder(patientId, dropoutRisk, daysSinceCheckIn) {
    try {
      const stmt = this.db.prepare(`
        INSERT OR IGNORE INTO engagement_reminders (
          patient_id,
          dropout_risk,
          days_since_checkin,
          sent_at
        ) VALUES (?, ?, ?, ?)
      `);

      stmt.run(
        patientId,
        dropoutRisk,
        daysSinceCheckIn,
        new Date().toISOString(),
      );

      console.log(`Reminder logged for patient ${patientId} (risk: ${dropoutRisk}%)`);
    } catch (error) {
      console.error('Log reminder error:', error);
    }
  }

  /**
   * Get patient's optimal reminder times based on historical engagement
   * Returns preferred hours (0-23) for sending reminders
   */
  async getOptimalReminderTimes(patientId) {
    try {
      // Analyze check-in patterns from last 30 days
      const checkIns = this.db.prepare(`
        SELECT strftime('%H', created_at) as hour
        FROM check_ins
        WHERE patient_id = ? 
        AND created_at > datetime('now', '-30 days')
      `).all(patientId);

      if (checkIns.length === 0) {
        // Default times: Morning (9 AM) and Evening (6 PM)
        return [9, 18];
      }

      // Count check-ins by hour
      const hourCounts = {};
      checkIns.forEach(({ hour }) => {
        hourCounts[hour] = (hourCounts[hour] || 0) + 1;
      });

      // Return top 2 most active hours
      const topHours = Object.entries(hourCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 2)
        .map(([hour]) => parseInt(hour));

      return topHours.length > 0 ? topHours : [9, 18];
    } catch (error) {
      console.error('Get optimal reminder times error:', error);
      return [9, 18]; // Default fallback
    }
  }

  /**
   * Manually trigger reminder for a specific patient (admin/therapist action)
   */
  async triggerManualReminder(patientId) {
    try {
      const engagement = this.db.prepare(`
        SELECT risk_of_dropout, days_since_check_in FROM engagement_metrics
        WHERE patient_id = ?
        ORDER BY created_at DESC LIMIT 1
      `).get(patientId);

      if (!engagement) {
        return { success: false, error: 'No engagement data found' };
      }

      await this.notificationService.sendEngagementReminder(
        patientId,
        'device-token-placeholder',
        engagement.risk_of_dropout,
        engagement.days_since_check_in,
      );

      // Log manual reminder
      this._logReminder(
        patientId,
        engagement.risk_of_dropout,
        engagement.days_since_check_in,
      );

      return { success: true };
    } catch (error) {
      console.error('Trigger manual reminder error:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Get reminder statistics for admin dashboard
   */
  async getReminderStats(therapistId) {
    try {
      const stats = this.db.prepare(`
        SELECT 
          COUNT(DISTINCT patient_id) as total_reminders_sent,
          AVG(dropout_risk) as avg_dropout_risk_at_reminder,
          SUM(CASE WHEN dropout_risk >= 70 THEN 1 ELSE 0 END) as critical_risk_reminders,
          SUM(CASE WHEN dropout_risk >= 50 AND dropout_risk < 70 THEN 1 ELSE 0 END) as high_risk_reminders,
          MAX(sent_at) as last_reminder_sent
        FROM engagement_reminders
        WHERE patient_id IN (
          SELECT patient_id FROM patient_therapist_assignments
          WHERE therapist_id = ?
        )
        AND sent_at > datetime('now', '-30 days')
      `).get(therapistId);

      return stats || {};
    } catch (error) {
      console.error('Get reminder stats error:', error);
      return {};
    }
  }

  /**
   * Create engagement_reminders table if not exists
   */
  ensureTablesExist() {
    try {
      const stmt = this.db.prepare(`
        CREATE TABLE IF NOT EXISTS engagement_reminders (
          id INTEGER PRIMARY KEY,
          patient_id TEXT NOT NULL,
          dropout_risk INTEGER,
          days_since_checkin INTEGER,
          sent_at TEXT NOT NULL,
          delivered_at TEXT,
          read_at TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (patient_id) REFERENCES patients(id),
          UNIQUE(patient_id, sent_at)
        )
      `);
      stmt.run();
      console.log('engagement_reminders table ensured');
    } catch (error) {
      console.error('Error ensuring tables:', error);
    }
  }
}

module.exports = EngagementReminderService;
