const express = require('express');
const WearableDataService = require('../services/WearableDataService');
const NotificationService = require('../services/NotificationService');
const EngagementReminderService = require('../services/EngagementReminderService');
const PDFReportService = require('../services/PDFReportService');
const Database = require('../database/Database');

const router = express.Router();
const db = new Database();
const wearableService = new WearableDataService();
const notificationService = new NotificationService();
const reminderService = new EngagementReminderService();
const pdfService = new PDFReportService();

/**
 * WEARABLE DATA ENDPOINTS
 * Real-time ingestion of health metrics from wearable devices
 * All data is REAL from devices, triggers immediate risk recalculation
 */

/**
 * POST /api/realtime/wearable/mood
 * Record real-time mood data from wearable
 * Expected: { patientId, moodScore: 1-10, timestamp?: ISO8601 }
 */
router.post('/wearable/mood', async (req, res) => {
  try {
    const { patientId, moodScore, timestamp } = req.body;

    if (!patientId || moodScore === undefined) {
      return res.status(400).json({ error: 'patientId and moodScore required' });
    }

    const result = await wearableService.recordMoodData(patientId, moodScore, timestamp);
    res.json({ success: true, data: result });
  } catch (error) {
    console.error('POST mood error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/realtime/wearable/anxiety
 * Record real-time anxiety data from wearable
 */
router.post('/wearable/anxiety', async (req, res) => {
  try {
    const { patientId, anxietyScore, timestamp } = req.body;

    if (!patientId || anxietyScore === undefined) {
      return res.status(400).json({ error: 'patientId and anxietyScore required' });
    }

    const result = await wearableService.recordAnxietyData(patientId, anxietyScore, timestamp);
    res.json({ success: true, data: result });
  } catch (error) {
    console.error('POST anxiety error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/realtime/wearable/sleep
 * Record real-time sleep data from wearable
 */
router.post('/wearable/sleep', async (req, res) => {
  try {
    const { patientId, sleepDuration, sleepQuality, timestamp } = req.body;

    if (!patientId || sleepDuration === undefined) {
      return res.status(400).json({ error: 'patientId and sleepDuration required' });
    }

    const result = await wearableService.recordSleepData(
      patientId,
      sleepDuration,
      sleepQuality || 5,
      timestamp,
    );
    res.json({ success: true, data: result });
  } catch (error) {
    console.error('POST sleep error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/realtime/wearable/heartrate
 * Record real-time heart rate data from wearable
 */
router.post('/wearable/heartrate', async (req, res) => {
  try {
    const { patientId, heartRate, isResting, timestamp } = req.body;

    if (!patientId || heartRate === undefined) {
      return res.status(400).json({ error: 'patientId and heartRate required' });
    }

    const result = await wearableService.recordHeartRateData(patientId, heartRate, isResting || false, timestamp);
    res.json({ success: true, data: result });
  } catch (error) {
    console.error('POST heartrate error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/realtime/wearable/activity
 * Record real-time activity data from wearable
 */
router.post('/wearable/activity', async (req, res) => {
  try {
    const { patientId, steps, activityMinutes, caloriesBurned, timestamp } = req.body;

    if (!patientId || steps === undefined) {
      return res.status(400).json({ error: 'patientId and steps required' });
    }

    const result = await wearableService.recordActivityData(
      patientId,
      steps,
      activityMinutes || 0,
      caloriesBurned || 0,
      timestamp,
    );
    res.json({ success: true, data: result });
  } catch (error) {
    console.error('POST activity error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/realtime/wearable/batch
 * Batch ingest multiple wearable data points
 * Expected: { patientId, dataPoints: [{ type, value, timestamp }...] }
 */
router.post('/wearable/batch', async (req, res) => {
  try {
    const { patientId, dataPoints } = req.body;

    if (!patientId || !Array.isArray(dataPoints)) {
      return res.status(400).json({ error: 'patientId and dataPoints array required' });
    }

    const result = await wearableService.ingestWearableBatch(patientId, dataPoints);
    res.json(result);
  } catch (error) {
    console.error('POST batch error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/realtime/wearable/summary/:patientId
 * Get wearable data summary (last 7 days)
 */
router.get('/wearable/summary/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;
    const summary = await wearableService.getWearableSummary(patientId);
    res.json({ success: true, summary });
  } catch (error) {
    console.error('GET wearable summary error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * NOTIFICATION ENDPOINTS
 * Real-time notification management for therapists
 */

/**
 * POST /api/realtime/notifications/register-device
 * Register device token for push notifications
 */
router.post('/notifications/register-device', async (req, res) => {
  try {
    const { therapistId, deviceToken, platform } = req.body;

    if (!therapistId || !deviceToken) {
      return res.status(400).json({ error: 'therapistId and deviceToken required' });
    }

    const success = await notificationService.registerDeviceToken(therapistId, deviceToken, platform || 'android');
    res.json({ success });
  } catch (error) {
    console.error('Register device error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/realtime/notifications/test-alert
 * Send test alert for configuration verification
 */
router.post('/notifications/test-alert', async (req, res) => {
  try {
    const { therapistId, patientName } = req.body;

    if (!therapistId) {
      return res.status(400).json({ error: 'therapistId required' });
    }

    const result = await notificationService.sendClinicalAlertNotification(
      therapistId,
      patientName || 'Test Patient',
      'severe_depression',
      'high',
      'This is a test notification to verify alert delivery',
      22,
      15,
    );

    res.json({ success: true, result });
  } catch (error) {
    console.error('Test alert error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * ENGAGEMENT REMINDER ENDPOINTS
 * Smart automated check-in reminders
 */

/**
 * POST /api/realtime/reminders/evaluate
 * Evaluate all patients and send reminders if needed
 * (Should be called periodically, e.g., every 30 minutes)
 */
router.post('/reminders/evaluate', async (req, res) => {
  try {
    const result = await reminderService.evaluateAndSendReminders();
    res.json(result);
  } catch (error) {
    console.error('Evaluate reminders error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/realtime/reminders/manual/:patientId
 * Manually trigger reminder for specific patient
 */
router.post('/reminders/manual/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;
    const result = await reminderService.triggerManualReminder(patientId);
    res.json(result);
  } catch (error) {
    console.error('Manual reminder error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/realtime/reminders/stats/:therapistId
 * Get reminder statistics for therapist
 */
router.get('/reminders/stats/:therapistId', async (req, res) => {
  try {
    const { therapistId } = req.params;
    const stats = await reminderService.getReminderStats(therapistId);
    res.json({ success: true, stats });
  } catch (error) {
    console.error('Get reminder stats error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * REPORT GENERATION ENDPOINTS
 */

/**
 * GET /api/realtime/reports/treatment/:patientId
 * Generate comprehensive treatment outcome report (PDF)
 */
router.get('/reports/treatment/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;
    const { therapistId } = req.query;

    if (!therapistId) {
      return res.status(400).json({ error: 'therapistId query parameter required' });
    }

    const result = await pdfService.generateTreatmentOutcomeReport(patientId, therapistId);

    if (result.success) {
      res.download(result.filepath, result.filename);
    } else {
      res.status(500).json({ error: 'Failed to generate report' });
    }
  } catch (error) {
    console.error('Generate treatment report error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/realtime/reports/progress/:patientId
 * Generate simple progress report (PDF)
 */
router.get('/reports/progress/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;
    const result = await pdfService.generateProgressReport(patientId);

    if (result.success) {
      res.download(result.filepath, result.filename);
    } else {
      res.status(500).json({ error: 'Failed to generate report' });
    }
  } catch (error) {
    console.error('Generate progress report error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/realtime/reports/wearable/:patientId
 * Generate wearable data summary report (PDF)
 */
router.get('/reports/wearable/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;
    const { days } = req.query;

    const result = await pdfService.generateWearableDataReport(patientId, parseInt(days) || 30);

    if (result.success) {
      res.download(result.filepath, result.filename);
    } else {
      res.status(500).json({ error: 'Failed to generate report' });
    }
  } catch (error) {
    console.error('Generate wearable report error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * HEALTH CHECK
 */
router.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    services: {
      wearable: 'active',
      notifications: 'active',
      reminders: 'active',
      reports: 'active',
    },
  });
});

module.exports = router;
