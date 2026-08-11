const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const Database = require('../database/Database');

/**
 * NotificationService - Real-time FCM notifications for therapists
 * Handles clinical alerts, engagement reminders, and delivery tracking
 * NO random values - all alerts based on actual clinical data
 */
class NotificationService {
  constructor() {
    try {
      if (!admin.apps.length) {
        // Production (Render): pass the service account as an env var, either as
        // raw JSON or base64-encoded (base64 avoids newline/escaping issues).
        // Local dev: GOOGLE_APPLICATION_CREDENTIALS points to the JSON file.
        const inlineJson = process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON;
        const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
        let serviceAccount = null;
        if (inlineJson) {
          const raw = inlineJson.trim();
          serviceAccount = JSON.parse(raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8'));
        } else if (credentialsPath) {
          const resolvedPath = path.resolve(process.cwd(), credentialsPath);
          serviceAccount = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
        }

        if (serviceAccount) {
          admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
            projectId: serviceAccount.project_id,
          });
        } else {
          admin.initializeApp();
        }
      }
      this.initialized = true;
    } catch (error) {
      console.warn('Firebase Admin SDK not initialized. Notifications disabled.', error.message);
      this.initialized = false;
    }
  }

  /**
   * Look up registered FCM tokens for a user from the device_tokens table.
   */
  _getTokensForUser(userId) {
    try {
      const db = Database.getInstance().getDB();
      const rows = db.prepare('SELECT token FROM device_tokens WHERE user_id = ?').all(userId);
      return rows.map((r) => r.token);
    } catch (error) {
      console.warn('Unable to read device_tokens:', error.message);
      return [];
    }
  }

  /**
   * Send a prepared message to a set of device tokens.
   * Returns delivery stats; invalid/expired tokens are removed.
   */
  async _sendToTokens(tokens, message) {
    if (!tokens.length) return { delivered: 0, queued: 0 };
    let delivered = 0;
    const staleTokens = [];
    for (const token of tokens) {
      try {
        await admin.messaging().send({ ...message, token });
        delivered += 1;
      } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
          staleTokens.push(token);
        }
      }
    }
    if (staleTokens.length) {
      try {
        const db = Database.getInstance().getDB();
        db.prepare('DELETE FROM device_tokens WHERE token = ?').run(staleTokens);
      } catch (error) {
        console.warn('Unable to prune stale device tokens:', error.message);
      }
    }
    return { delivered, queued: tokens.length - delivered };
  }

  /**
   * Register device token for therapist push notifications
   */
  async registerDeviceToken(therapistId, deviceToken, platform = 'android') {
    if (!this.initialized) return false;
    try {
      const { v4: uuidv4 } = require('uuid');
      const db = Database.getInstance().getDB();
      const normalized =
        platform === 'ios' ? 'ios' : platform === 'web' ? 'web' : 'android';
      db.prepare('DELETE FROM device_tokens WHERE user_id = ? AND token = ?')
        .run(therapistId, deviceToken);
      db.prepare(`
        INSERT INTO device_tokens (id, user_id, token, platform)
        VALUES (?, ?, ?, ?)
      `).run(uuidv4(), therapistId, deviceToken, normalized);
      console.log(`Device registered: Therapist ${therapistId}, Token: ${deviceToken.substring(0, 20)}..., Platform: ${normalized}`);
      return true;
    } catch (error) {
      console.error('Register device token error:', error);
      return false;
    }
  }

  /**
   * Send clinical alert notification to therapist
   * Called immediately when alert is created (real-time)
   */
  async sendClinicalAlertNotification(
    therapistId,
    patientName,
    alertType,
    severity,
    description,
    triggeredValue,
    thresholdValue,
  ) {
    if (!this.initialized) {
      console.log(`[NOTIFICATION QUEUED] Alert for therapist ${therapistId}: ${patientName} - ${alertType}`);
      return { queued: true, delivered: false };
    }

    try {
      const title = this._getTitleForAlertType(alertType, severity);
      const body = `${patientName}: ${description}`;
      const priority = severity === 'critical' ? 'high' : 'normal';

      // Build rich notification with custom data
      const message = {
        notification: {
          title,
          body,
        },
        data: {
          alertType,
          severity,
          patientName,
          triggeredValue: triggeredValue.toString(),
          thresholdValue: thresholdValue.toString(),
          timestamp: new Date().toISOString(),
          notificationType: 'clinical_alert',
        },
        android: {
          priority: priority === 'high' ? 'high' : 'normal',
          notification: {
            sound: 'default',
            channelId: severity === 'critical' ? 'clinical_critical' : 'clinical_alerts',
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        apns: {
          headers: {
            'apns-priority': priority === 'high' ? '10' : '5',
          },
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
        webpush: {
          headers: {
            TTL: '3600',
          },
          notification: {
            title,
            body,
            icon: '/notification-icon.png',
            badge: '/notification-badge.png',
            tag: `alert-${alertType}`,
          },
        },
      };

      // Send to the therapist's registered device tokens.
      const tokens = this._getTokensForUser(therapistId);
      const result = await this._sendToTokens(tokens, message);
      if (result.delivered > 0) {
        console.log(`[FCM NOTIFICATION SENT] To ${result.delivered} device(s) for therapist ${therapistId}: ${title}`);
        console.log(`  Patient: ${patientName}`);
        console.log(`  Severity: ${severity}`);
        console.log(`  Triggered: ${triggeredValue}, Threshold: ${thresholdValue}`);
        return { delivered: true, queued: false };
      }
      console.log(`[NOTIFICATION QUEUED] No reachable device for therapist ${therapistId}: ${title}`);
      return { queued: true, delivered: false };
    } catch (error) {
      console.error('Send clinical alert notification error:', error);
      // Queue for retry in production
      return { delivered: false, queued: true, error: error.message };
    }
  }

  /**
   * Send a push notification for a new chat message to the recipient.
   * Both patients and therapists use this; messages arrive with the FCM
   * data payload so the app can deep-link into the conversation.
   */
  async sendChatMessageNotification({
    recipientUserId,
    senderName,
    body,
    conversationPair, // sorted: [userA, userB] used to build the Firestore conv id
    senderId,
    recipientId,
  }) {
    const message = {
      notification: {
        title: senderName || 'New message',
        body: (body || '').length > 200 ? `${(body || '').slice(0, 197)}...` : (body || ''),
      },
      data: {
        notificationType: 'chat_message',
        senderId: senderId || '',
        recipientId: recipientId || '',
        senderName: senderName || '',
        body: body || '',
        conversationId:
          Array.isArray(conversationPair) && conversationPair.length === 2
            ? [conversationPair[0], conversationPair[1]].sort().join('__')
            : '',
        timestamp: new Date().toISOString(),
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'chat_messages',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
      webpush: {
        headers: { TTL: '3600' },
        notification: {
          title: senderName || 'New message',
          body: (body || '').length > 200 ? `${(body || '').slice(0, 197)}...` : (body || ''),
          icon: '/notification-icon.png',
          badge: '/notification-badge.png',
          tag: `msg-${senderId}`,
        },
      },
    };

    if (!this.initialized) {
      console.log(`[CHAT NOTIFICATION QUEUED] To ${recipientUserId}: ${senderName} - ${(body || '').slice(0, 40)}`);
      return { queued: true, delivered: false };
    }

    try {
      const tokens = this._getTokensForUser(recipientUserId);
      if (!tokens.length) {
        console.log(`[CHAT NOTIFICATION QUEUED] No device for ${recipientUserId}`);
        return { queued: true, delivered: false };
      }
      const result = await this._sendToTokens(tokens, message);
      if (result.delivered > 0) {
        console.log(`[CHAT NOTIFICATION SENT] ${result.delivered} device(s) for ${recipientUserId}`);
        return { delivered: true, queued: false };
      }
      return { queued: true, delivered: false };
    } catch (error) {
      console.error('Send chat message notification error:', error);
      return { delivered: false, queued: true, error: error.message };
    }
  }

  /**
   * Send engagement reminder to patient
   * Smart timing based on engagement risk and patient habits
   */
  async sendEngagementReminder(
    patientId,
    deviceToken,
    dropoutRisk,
    daysSinceCheckIn,
  ) {
    if (!this.initialized) {
      console.log(`[REMINDER QUEUED] Patient ${patientId} - Days since check-in: ${daysSinceCheckIn}`);
      return { queued: true, delivered: false };
    }

    try {
      const title = this._getReminderTitle(dropoutRisk, daysSinceCheckIn);
      const body = this._getReminderBody(dropoutRisk);

      const message = {
        notification: {
          title,
          body,
        },
        data: {
          notificationType: 'engagement_reminder',
          dropoutRisk: dropoutRisk.toString(),
          daysSinceCheckIn: daysSinceCheckIn.toString(),
          timestamp: new Date().toISOString(),
        },
        android: {
          priority: dropoutRisk > 60 ? 'high' : 'normal',
          notification: {
            sound: 'default',
            channelId: 'engagement_reminders',
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
      };

      // Send to the patient's registered device tokens.
      const tokens = deviceToken
        ? [deviceToken]
        : this._getTokensForUser(patientId);
      const result = await this._sendToTokens(tokens, message);
      if (result.delivered > 0) {
        console.log(`[ENGAGEMENT REMINDER] Sent to ${result.delivered} device(s) for patient ${patientId}`);
        console.log(`  Dropout Risk: ${dropoutRisk}%`);
        console.log(`  Message: ${title}`);
        return { delivered: true, queued: false };
      }
      console.log(`[REMINDER QUEUED] Patient ${patientId} - Days since check-in: ${daysSinceCheckIn}`);
      return { queued: true, delivered: false };
    } catch (error) {
      console.error('Send engagement reminder error:', error);
      return { delivered: false, queued: true, error: error.message };
    }
  }

  /**
   * Send treatment milestone notification
   * Triggered when patient reaches remission or significant progress
   */
  async sendTreatmentMilestoneNotification(
    therapistId,
    patientName,
    milestoneType,
    responsePercentage,
    currentScore,
  ) {
    if (!this.initialized) {
      console.log(`[MILESTONE QUEUED] ${patientName} achieved ${milestoneType}`);
      return { queued: true, delivered: false };
    }

    try {
      const title = milestoneType === 'remission' 
        ? '🎉 Patient in Remission!' 
        : '📈 Significant Treatment Progress';
      
      const body = `${patientName}: ${responsePercentage}% improvement (PHQ-9: ${currentScore})`;

      const message = {
        notification: {
          title,
          body,
        },
        data: {
          notificationType: 'treatment_milestone',
          milestoneType,
          responsePercentage: responsePercentage.toString(),
          currentScore: currentScore.toString(),
          patientName,
          timestamp: new Date().toISOString(),
        },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'treatment_milestones',
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
      };

      // Send to the therapist's registered device tokens.
      const tokens = this._getTokensForUser(therapistId);
      const result = await this._sendToTokens(tokens, message);
      if (result.delivered > 0) {
        console.log(`[TREATMENT MILESTONE] ${title} to ${result.delivered} device(s) for therapist ${therapistId}`);
        return { delivered: true, queued: false };
      }
      console.log(`[MILESTONE QUEUED] ${title} for therapist ${therapistId} - no reachable device`);
      return { queued: true, delivered: false };
    } catch (error) {
      console.error('Send treatment milestone error:', error);
      return { delivered: false, queued: true };
    }
  }

  /**
   * Record notification delivery and read status
   */
  async recordNotificationEvent(
    therapistId,
    notificationId,
    event, // 'delivered', 'read', 'dismissed'
  ) {
    try {
      console.log(`Notification event: ${event} for notification ${notificationId} (Therapist: ${therapistId})`);
      // In production, update notification_delivery_log table
      return true;
    } catch (error) {
      console.error('Record notification event error:', error);
      return false;
    }
  }

  // Helper methods
  _getTitleForAlertType(alertType, severity) {
    const titles = {
      sos: '🚨 SOS - Patient Needs Immediate Support',
      severe_depression: 'Severe Depression Alert',
      poor_treatment_response: 'Poor Treatment Response',
      high_dropout_risk: 'High Dropout Risk',
      critical_risk_factors: 'Critical Risk Factors',
      missed_appointment: 'Missed Appointment',
      medication_non_adherence: 'Medication Non-Adherence',
    };
    return titles[alertType] || 'Clinical Alert';
  }

  _getReminderTitle(dropoutRisk, daysSinceCheckIn) {
    if (dropoutRisk >= 70) {
      return 'We Miss You! 💙';
    }
    if (dropoutRisk >= 50) {
      return 'Time for a Check-in? 📝';
    }
    if (daysSinceCheckIn > 7) {
      return 'Weekly Check-in Available 🌟';
    }
    return 'How Are You Feeling? ✨';
  }

  _getReminderBody(dropoutRisk) {
    if (dropoutRisk >= 70) {
      return "We've noticed you haven't checked in recently. Your therapist is here for support. 💚";
    }
    if (dropoutRisk >= 50) {
      return 'A quick check-in helps your therapist track your progress. Takes just 2 minutes.';
    }
    return 'Share how you\'re feeling this week. It helps with your treatment plan.';
  }
}

module.exports = NotificationService;
