'use strict';

const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions/v2');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { db } = require('../admin');
const { COLLECTIONS } = require('../logic/constants');
const vitals = require('../logic/vitals');
const clinical = require('../logic/clinical');

const TRIGGER_OPTS = { retry: true };

/**
 * Creates crisis_events/{crisisId}, or — if it already exists (a retry, or the
 * patient app wrote the same deterministic id first, e.g. the immediate
 * on-device PHQ-9 alert) — merges server-verified facts without ever throwing
 * on the conflict (retry:true would otherwise loop) and without touching
 * acknowledged/acknowledgedAt/acknowledgedBy/timestamp. Severity only escalates.
 * The push is sent exactly once by onCrisisEventCreated regardless of creator.
 * @return {Promise<'created'|'merged'|'unchanged'>}
 */
async function createOrMergeCrisis(crisisId, fields, verified) {
  const ref = db().collection(COLLECTIONS.CRISIS_EVENTS).doc(crisisId);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      tx.create(ref, { ...fields, acknowledged: false, timestamp: FieldValue.serverTimestamp() });
      return 'created';
    }
    const update = clinical.planCrisisMerge(snap.data(), verified);
    if (!update) return 'unchanged';
    tx.update(ref, { ...update, 'serverVerified.verifiedAt': FieldValue.serverTimestamp() });
    return 'merged';
  });
}

function logUnassigned(patientId, crisisId) {
  logger.error('CRISIS EVENT FOR PATIENT WITHOUT THERAPIST — no clinician will be notified',
    { patientId, crisisId });
}

/** vitals/{vitalId} created: latestVitals snapshot + threshold alert. */
const onVitalCreated = onDocumentCreated(
  { document: `${COLLECTIONS.VITALS}/{vitalId}`, ...TRIGGER_OPTS },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const vitalId = event.params.vitalId;
    const raw = snap.data();
    const check = vitals.validateVitalReading(raw);
    if (!check.ok) {
      const log = check.sensorError ? logger.warn : logger.error;
      log(check.sensorError ? 'vital rejected as sensor error (no alert)' : 'invalid vital document',
        { vitalId, patientId: raw && raw.patientId, type: raw && raw.type, reason: check.reason });
      return;
    }
    const reading = check.reading;
    const spec = vitals.VITAL_SPECS[reading.type];
    const userRef = db().collection(COLLECTIONS.USERS).doc(reading.patientId);
    const cooldownRef = db().collection(COLLECTIONS.ALERT_COOLDOWNS).doc(reading.patientId);
    const crisisId = vitals.crisisIdForVital(vitalId);
    const crisisRef = db().collection(COLLECTIONS.CRISIS_EVENTS).doc(crisisId);

    const outcome = await db().runTransaction(async (tx) => {
      const [userSnap, cdSnap, crisisSnap] = await tx.getAll(userRef, cooldownRef, crisisRef);
      if (!userSnap.exists) return { status: 'no-user' };

      const updates = {};
      const prev = vitals.toMillis(userSnap.get(`latestVitals.${spec.snapshotKey}.measuredAt`));
      if (vitals.isNewerReading(prev, reading.measuredAtMillis)) {
        updates[`latestVitals.${spec.snapshotKey}`] = {
          value: reading.value,
          measuredAt: Timestamp.fromMillis(reading.measuredAtMillis),
        };
      }

      const { thresholds, warnings } = vitals.resolveThresholds(userSnap.get('vitalThresholds'));
      const evaluation = vitals.evaluateVital(reading, thresholds);
      let status = 'normal';
      if (evaluation) {
        if (crisisSnap.exists) {
          status = 'duplicate';
        } else {
          const field = vitals.cooldownField(reading.type, evaluation.eventType);
          const last = vitals.toMillis(cdSnap.exists ? cdSnap.get(field) : null);
          const now = Date.now();
          if (vitals.isInCooldown(last, now)) {
            status = 'cooldown';
          } else {
            const patientName = String(userSnap.get('name') || 'Patient');
            const therapistId = userSnap.get('therapistId') || null;
            const { title, message } = vitals.describeVitalAlert(patientName, reading, evaluation);
            tx.create(crisisRef, {
              patientId: reading.patientId,
              therapistId,
              patientName,
              eventType: evaluation.eventType,
              severity: evaluation.severity,
              title,
              message,
              vital: {
                type: reading.type,
                value: reading.value,
                unit: reading.unit,
                threshold: evaluation.threshold,
              },
              acknowledged: false,
              timestamp: FieldValue.serverTimestamp(),
              source: 'vital',
              sourceId: vitalId,
            });
            tx.set(cooldownRef, {
              patientId: reading.patientId,
              [field]: Timestamp.fromMillis(now),
            }, { merge: true });
            status = therapistId ? 'alerted' : 'alerted-unassigned';
          }
        }
      }
      if (Object.keys(updates).length) tx.update(userRef, updates);
      return { status, warnings };
    });

    if (outcome.status === 'no-user') {
      logger.error('vital for unknown patient', { vitalId, patientId: reading.patientId });
      return;
    }
    for (const w of outcome.warnings) {
      logger.warn('invalid vitalThresholds override', { patientId: reading.patientId, warning: w });
    }
    if (outcome.status === 'alerted-unassigned') logUnassigned(reading.patientId, crisisId);
    logger.info('vital processed', {
      vitalId, patientId: reading.patientId, type: reading.type, status: outcome.status,
    });
  });

async function raiseClinicalCrisis(source, docId, data, evaluation) {
  const patientId = data && data.patientId;
  if (typeof patientId !== 'string' || !patientId) {
    logger.error(`${source} without patientId; cannot raise crisis`, { docId });
    return;
  }
  const userSnap = await db().collection(COLLECTIONS.USERS).doc(patientId).get();
  const patientName = String((userSnap.exists && userSnap.get('name')) || 'Patient');
  // Authoritative link is the users doc, not the (client-written) source doc.
  const therapistId = (userSnap.exists && userSnap.get('therapistId')) || data.therapistId || null;
  const crisisId = source === 'assessment' ?
    clinical.crisisIdForAssessment(docId) : clinical.crisisIdForDailyLog(docId);
  const { title, message } = clinical.describeClinicalAlert(patientName, source, evaluation);
  const outcome = await createOrMergeCrisis(crisisId, {
    patientId,
    therapistId,
    patientName,
    eventType: evaluation.eventType,
    severity: evaluation.severity,
    title,
    message,
    source,
    sourceId: docId,
  }, evaluation);
  if (outcome === 'created' && !therapistId) logUnassigned(patientId, crisisId);
  logger.info(`${source} crisis evaluation`, {
    docId, patientId, eventType: evaluation.eventType, severity: evaluation.severity, outcome,
  });
}

/** daily_logs/{logId} created: riskScore >= 75 => high_risk crisis. */
const onDailyLogCreated = onDocumentCreated(
  { document: `${COLLECTIONS.DAILY_LOGS}/{logId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    const data = event.data.data();
    const evaluation = clinical.evaluateDailyLog(data);
    if (!evaluation) return;
    await raiseClinicalCrisis('daily_log', event.params.logId, data, evaluation);
  });

/**
 * daily_logs/{logId} updated. The patient app merges ML results (mlRisk.riskScore,
 * a recomputed riskScore) into the log AFTER creating it, so a crisis-level
 * score may only appear on update. Same deterministic crisis id => no duplicate.
 * (Not in the contract's function list; additive safety net.)
 */
const onDailyLogUpdated = onDocumentUpdated(
  { document: `${COLLECTIONS.DAILY_LOGS}/{logId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    const before = event.data.before.data();
    const after = event.data.after.data();
    const prevRisk = clinical.extractRiskScore(before);
    const nextRisk = clinical.extractRiskScore(after);
    if (nextRisk === null || (prevRisk !== null && nextRisk <= prevRisk)) return;
    const evaluation = clinical.evaluateDailyLog(after);
    if (!evaluation) return;
    await raiseClinicalCrisis('daily_log', event.params.logId, after, evaluation);
  });

/** clinical_assessments/{assessmentId} created: PHQ-9 >= 20, item 9 > 0, risk >= 75. */
const onAssessmentCreated = onDocumentCreated(
  { document: `${COLLECTIONS.ASSESSMENTS}/{assessmentId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    const data = event.data.data();
    const phq = clinical.extractPhq9(data);
    if (phq.total === null && phq.item9 === null && /phq/i.test(String(data.type || ''))) {
      logger.error('PHQ assessment without readable score/items; cannot screen for crisis',
        { assessmentId: event.params.assessmentId, patientId: data.patientId });
    }
    const evaluation = clinical.evaluateAssessment(data);
    if (!evaluation) return;
    await raiseClinicalCrisis('assessment', event.params.assessmentId, data, evaluation);
  });

module.exports = {
  onVitalCreated,
  onDailyLogCreated,
  onDailyLogUpdated,
  onAssessmentCreated,
  createOrMergeCrisis,
};
