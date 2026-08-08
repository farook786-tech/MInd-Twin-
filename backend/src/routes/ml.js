const express = require('express');
const axios = require('axios');
const DatabaseService = require('../database/Database');
const { authMiddleware, canAccessPatient } = require('../middleware/auth');
const TokenBucketMiddleware = require('../middleware/TokenBucketMiddleware');
const router = express.Router();

// AI endpoints proxy to paid external providers; cap usage per authenticated user.
const aiRateLimit = TokenBucketMiddleware({ capacity: 20, windowMs: 60 * 60 * 1000 });

const ML_BASE_URL = process.env.ML_SERVICE_URL || 'http://127.0.0.1:8000';
const ML_TIMEOUT_MS = 1500;

// Hard phrases ALWAYS escalate, even if an idiom is present.
const HARD_PHRASES = [
  'kill myself',
  'end my life',
  'take my life',
  'end it all',
  'hurt myself',
  'hurting myself',
  'self harm',
  'self-harm',
  'suicide',
  'suicidal',
  'not wake up tomorrow',
  'better off dead',
  'planning to kill',
  'going to kill myself',
];

// Soft phrases escalate UNLESS an idiom is present.
const SOFT_PHRASES = [
  'want to die',
  'wanna die',
  'rather be dead',
  'wish i was dead',
  'no reason to live',
  'give up on life',
  'nobody would notice',
  'no one would notice',
  'everything is pointless',
  'life is pointless',
  'want the pain to stop',
  'stop living',
  'stop existing',
];

// Figurative idioms: suppress soft/model escalation.
const IDIOM_PATTERNS = [
  'dying laughing',
  'die laughing',
  'died laughing',
  'die of laughter',
  'killing me',
  'killed me',
  'would kill for',
  'kill for a',
  'dead tired',
  'died of',
  'killed it',
  'killing it',
  'to die for',
];

function hasAny(text, patterns) {
  return patterns.filter((p) => text.includes(p));
}

/**
 * POST /api/ml/predict
 * Routes a message to the FastAPI crisis model and applies the
 * hard/soft phrase + idiom decision matrix.
 * If the ML service is down, returns { available: false } so the
 * client can fall back to local detection.
 */
router.post('/predict', authMiddleware, aiRateLimit, async (req, res) => {
  try {
    const { text, patientId, recentHistory } = req.body;

    if (!text || typeof text !== 'string') {
      return res.status(400).json({ success: false, error: 'text is required' });
    }

    // Patients may only run predictions for their own history.
    if (patientId && !canAccessPatient(req, patientId)) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    let modelResult;
    try {
      const response = await axios.post(
        `${ML_BASE_URL}/predict`,
        { text },
        { timeout: ML_TIMEOUT_MS }
      );
      modelResult = response.data;
    } catch (error) {
      console.warn('[ML bridge] ML service unavailable:', error.message);
      return res.status(200).json({
        success: true,
        available: false,
        decision: { escalate: false, reason: 'ml_service_unavailable' },
      });
    }

    const lower = text.toLowerCase();
    const hardHits = hasAny(lower, HARD_PHRASES);
    const softHits = hasAny(lower, SOFT_PHRASES);
    const idiomHits = hasAny(lower, IDIOM_PATTERNS);
    const modelCrisis = !!modelResult.crisis_detected;
    const probability = modelResult.probability_crisis || 0;

    const escalate = hardHits.length > 0 || ((modelCrisis || softHits.length > 0) && idiomHits.length === 0);

    let severity = 'low';
    let triggerLayer = 'none';
    if (hardHits.length > 0) {
      triggerLayer = 'phrase_hard';
      severity = probability >= 0.9 ? 'critical' : 'high';
    } else if (escalate) {
      triggerLayer = softHits.length > 0 ? 'phrase_soft' : 'model';
      severity = probability >= 0.75 ? 'high' : 'moderate';
    }

    res.json({
      success: true,
      available: true,
      model_version: modelResult.model_version || 'unknown',
      decision: {
        escalate,
        severity,
        confidence: probability,
        trigger_layer: triggerLayer,
        matched_phrases: [...hardHits, ...softHits],
        idiom_suppressed: idiomHits.length > 0,
      },
    });
  } catch (error) {
    console.error('[ML bridge] Error:', error);
    res.status(500).json({ success: false, error: 'ML bridge error' });
  }
});

// Confidence for a stored recommendation based on its evidence level.
function confidenceForEvidence(evidenceLevel) {
  const level = String(evidenceLevel || '').trim().toUpperCase();
  if (level.startsWith('A')) return 0.9;
  if (level.startsWith('B')) return 0.75;
  return 0.6;
}

// Evidence-based default interventions ranked from a patient's latest scores.
function defaultInterventions(wellbeingScore, moodScore) {
  const wellbeing = wellbeingScore ?? 70;
  const mood = moodScore ?? 5;

  const list = [];
  if (wellbeing < 50 || mood < 4) {
    list.push({
      title: 'Crisis safety planning',
      description: 'Co-create a personalized safety plan with emergency contacts and coping strategies.',
      confidence: 0.92,
    });
  }
  list.push({
    title: 'Cognitive behavioral therapy (CBT)',
    description: 'Weekly CBT sessions focused on thought restructuring and behavioral activation.',
    confidence: 0.86,
  });
  list.push({
    title: 'Daily mood & wellbeing journaling',
    description: 'Guided daily check-ins to track mood, sleep, and anxiety trends over time.',
    confidence: 0.78,
  });
  if (wellbeing < 70) {
    list.push({
      title: 'Sleep hygiene coaching',
      description: 'Personalized sleep schedule and relaxation routine to improve rest quality.',
      confidence: 0.72,
    });
  }
  list.push({
    title: 'Peer support group',
    description: 'Weekly moderated support group for shared experiences and social connection.',
    confidence: 0.64,
  });
  return list;
}

/**
 * POST /api/ml/recommend-intervention
 * Returns the top 3 evidence-based interventions for a patient, preferring
 * stored therapist-authored recommendations when they exist.
 */
router.post('/recommend-intervention', authMiddleware, aiRateLimit, async (req, res) => {
  try {
    const { patientId } = req.body;

    if (!patientId) {
      return res.status(400).json({ success: false, error: 'patientId is required' });
    }

    if (!canAccessPatient(req, patientId)) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    const database = DatabaseService.getInstance().getDB();

    // Clients may pass the internal patient id or the Firebase UID.
    const patient = database.prepare(
      'SELECT * FROM patients WHERE id = ? OR user_id = ? LIMIT 1'
    ).get(patientId, patientId);

    const interventions = [];

    if (patient) {
      const stored = database.prepare(
        'SELECT * FROM intervention_recommendations WHERE patient_id = ? ORDER BY created_at DESC'
      ).all(patient.id);

      for (const rec of stored) {
        interventions.push({
          title: rec.recommendation_type,
          description: rec.description,
          confidence: confidenceForEvidence(rec.evidence_level),
          evidence_level: rec.evidence_level,
        });
      }

      if (interventions.length === 0) {
        const latest = database.prepare(
          'SELECT * FROM daily_logs WHERE patient_id = ? ORDER BY created_at DESC LIMIT 1'
        ).get(patient.id);
        const wellbeing = latest?.wellbeing_score ?? patient.wellbeing_score ?? 70;
        const mood = latest?.mood_score ?? 5;
        interventions.push(...defaultInterventions(wellbeing, mood));
      }
    } else {
      interventions.push(...defaultInterventions(70, 5));
    }

    res.json({
      success: true,
      topRecommendations: interventions.slice(0, 3),
    });
  } catch (error) {
    console.error('[ML bridge] recommend-intervention error:', error);
    res.status(500).json({ success: false, error: 'Intervention recommendation failed' });
  }
});

module.exports = router;