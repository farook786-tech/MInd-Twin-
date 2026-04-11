const express = require('express');
const { v4: uuidv4 } = require('uuid');
const ClinicalService = require('../services/ClinicalService');
const DatabaseService = require('../database/Database');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();
const clinicalService = new ClinicalService();

/**
 * POST /api/clinical/phq9
 * Submit PHQ-9 Assessment (Hospital-Grade Clinical Assessment)
 * Request: { patientId, therapistId, responses: [0-3, ...9 items], notes }
 */
router.post('/phq9', (req, res) => {
  try {
    const {
      patientId,
      therapistId,
      responses,
      notes,
    } = req.body;

    if (!patientId || !therapistId || !Array.isArray(responses)) {
      return res.status(400).json({
        error: 'patientId, therapistId, and responses array are required',
      });
    }

    const result = clinicalService.createPHQ9Assessment(
      patientId,
      therapistId,
      responses,
      notes
    );

    res.status(201).json({
      success: true,
      assessment: result,
    });
  } catch (error) {
    console.error('PHQ-9 assessment error:', error);
    res.status(400).json({ error: error.message });
  }
});

/**
 * GET /api/clinical/assessment-history/:patientId
 * Get all PHQ-9 assessments for patient (time series)
 */
router.get('/assessment-history/:patientId', (req, res) => {
  try {
    const { patientId } = req.params;

    const assessments = db.getDB().prepare(`
      SELECT id, score, severity, is_baseline, assessment_date, notes
      FROM phq9_assessments
      WHERE patient_id = ?
      ORDER BY assessment_date ASC
    `).all(patientId);

    res.json({
      success: true,
      assessments,
      count: assessments.length,
    });
  } catch (error) {
    console.error('Assessment history error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/clinical/treatment-response/:patientId
 * Get treatment response metrics (baseline vs current)
 */
router.get('/treatment-response/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;

    const response = db.getDB().prepare(`
      SELECT * FROM treatment_responses
      WHERE patient_id = ?
      ORDER BY last_updated DESC LIMIT 1
    `).get(patientId);

    if (!response) {
      return res.json({
        success: true,
        message: 'No treatment response data yet (need baseline + follow-up)',
        response: null,
      });
    }

    res.json({
      success: true,
      response,
    });
  } catch (error) {
    console.error('Treatment response error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/clinical/risk-factors/:patientId
 * Get real-time clinical risk factors
 */
router.get('/risk-factors/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;

    // Calculate fresh risk factors
    const riskFactors = await clinicalService.calculateClinicalRiskFactors(patientId);

    res.json({
      success: true,
      riskFactors,
    });
  } catch (error) {
    console.error('Risk factors error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/clinical/engagement/:patientId
 * Get patient engagement metrics (dropout risk)
 */
router.get('/engagement/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;

    const engagement = await clinicalService.calculateEngagementRisk(patientId);

    res.json({
      success: true,
      engagement,
    });
  } catch (error) {
    console.error('Engagement error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/clinical/summary/:patientId
 * Get comprehensive treatment summary (all metrics)
 */
router.get('/summary/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;

    const summary = await clinicalService.getTreatmentSummary(patientId);

    res.json({
      success: true,
      summary,
    });
  } catch (error) {
    console.error('Treatment summary error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/clinical/alerts/:therapistId
 * Get all active clinical alerts for therapist
 */
router.get('/alerts/:therapistId', (req, res) => {
  try {
    const { therapistId } = req.params;

    const alerts = clinicalService.getActiveAlerts(therapistId);

    res.json({
      success: true,
      alerts,
      count: alerts.length,
    });
  } catch (error) {
    console.error('Alerts fetch error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/clinical/alerts/:alertId/acknowledge
 * Acknowledge a clinical alert
 */
router.post('/alerts/:alertId/acknowledge', (req, res) => {
  try {
    const { alertId } = req.params;
    const { actionTaken } = req.body;

    const database = db.getDB();
    database.prepare(`
      UPDATE clinical_alerts
      SET status = 'acknowledged', acknowledged_at = datetime('now'), action_taken = ?
      WHERE id = ?
    `).run(actionTaken || null, alertId);

    res.json({
      success: true,
      message: 'Alert acknowledged',
    });
  } catch (error) {
    console.error('Alert acknowledgement error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/clinical/interventions
 * Record evidence-based intervention recommendation
 */
router.post('/interventions', (req, res) => {
  try {
    const {
      patientId,
      therapistId,
      type,
      evidenceLevel,
      description,
      cbtInterventions,
      medicationSuggestions,
      lifestyleRecommendations,
    } = req.body;

    if (!patientId || !type || !evidenceLevel) {
      return res.status(400).json({
        error: 'patientId, type, and evidenceLevel are required',
      });
    }

    const interventionId = uuidv4();
    db.getDB().prepare(`
      INSERT INTO intervention_recommendations (
        id, patient_id, therapist_id, recommendation_type, evidence_level,
        description, cbt_interventions, medication_suggestions,
        lifestyle_recommendations
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      interventionId,
      patientId,
      therapistId || null,
      type,
      evidenceLevel,
      description || null,
      cbtInterventions ? JSON.stringify(cbtInterventions) : null,
      medicationSuggestions ? JSON.stringify(medicationSuggestions) : null,
      lifestyleRecommendations ? JSON.stringify(lifestyleRecommendations) : null
    );

    res.status(201).json({
      success: true,
      interventionId,
      message: 'Intervention recommendation recorded',
    });
  } catch (error) {
    console.error('Intervention creation error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/clinical/interventions/:patientId
 * Get all intervention recommendations for patient
 */
router.get('/interventions/:patientId', (req, res) => {
  try {
    const { patientId } = req.params;

    const interventions = db.getDB().prepare(`
      SELECT * FROM intervention_recommendations
      WHERE patient_id = ?
      ORDER BY created_at DESC
    `).all(patientId);

    res.json({
      success: true,
      interventions,
      count: interventions.length,
    });
  } catch (error) {
    console.error('Interventions fetch error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/clinical/calculate-all-metrics/:patientId
 * Recalculate all clinical metrics for a patient (runs all assessments)
 * Useful for batch processing or scheduled updates
 */
router.post('/calculate-all-metrics/:patientId', async (req, res) => {
  try {
    const { patientId } = req.params;

    const results = await Promise.all([
      clinicalService.calculateEngagementRisk(patientId),
      clinicalService.calculateClinicalRiskFactors(patientId),
    ]);

    res.json({
      success: true,
      metrics: {
        engagement: results[0],
        riskFactors: results[1],
      },
    });
  } catch (error) {
    console.error('Metrics calculation error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
