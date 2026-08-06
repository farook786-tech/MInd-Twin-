const express = require('express');
const axios = require('axios');
const router = express.Router();

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
router.post('/predict', async (req, res) => {
  try {
    const { text, patientId, recentHistory } = req.body;

    if (!text || typeof text !== 'string') {
      return res.status(400).json({ success: false, error: 'text is required' });
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

module.exports = router;
