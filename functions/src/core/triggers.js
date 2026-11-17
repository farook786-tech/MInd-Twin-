'use strict';

/**
 * Core logic of the Firestore / Auth triggers, independent of the event
 * source. Hosts:
 *  - Cloud Functions (Blaze): functions/src/triggers/*.js adapt CloudEvents.
 *  - Backend runner (Spark):  backend/src/firebase/triggerRunner.js feeds
 *    realtime-listener changes.
 *
 * Handler shapes
 *   created handlers:  (snap, ctx)
 *   change handlers:   ({before, after}, ctx)   before/after may be null
 * where snap is DocumentSnapshot-like: {id, data(), ref?, exists?}, and
 * ctx = {params?: object, eventId?: string, eventTime?: number (ms)}.
 *   - params: path params (vitalId, logId, chatId, messageId, appointmentId...);
 *     defaults to snap.id where unambiguous.
 *   - eventId: unique, DETERMINISTIC id of this change (Cloud Functions event
 *     id, or `<docId>_<updateTime>` in the runner). It keys push receipts, so
 *     every process handling the same change must derive the same value.
 *   - eventTime: when the change was committed (ms); old chat/appointment
 *     pushes are dropped.
 *
 * Every handler is idempotent: crisis docs have deterministic ids and every
 * push is guarded by push_receipts/{key}. Throwing means "retry later".
 */

const { COLLECTIONS, CHANNELS, PUSH_TYPES } = require('../logic/constants');
const vitals = require('../logic/vitals');
const clinical = require('../logic/clinical');
const { buildMeetingUrl } = require('../logic/inviteCode');
const {
  planAppointmentEffects, needsConflictCheck, findOverlaps, MAX_DURATION_MIN,
} = require('../logic/appointments');

const { toMillis } = vitals;

// Chat / appointment pushes older than this are dropped instead of retried
// (a stale "new message" push hours later is noise). Crisis pushes never expire.
const MAX_NON_CRITICAL_AGE_MS = 6 * 60 * 60 * 1000;

const DEFAULT_CRISIS_TITLES = {
  sos: 'SOS',
  checkin_crisis: 'Check-in crisis',
  chat_crisis: 'Crisis language in chat',
  high_risk: 'High risk',
  phq9_severe: 'PHQ-9 alert',
  vital_high: 'Vital sign high',
  vital_low: 'Vital sign low',
  cssrs_high: 'C-SSRS high risk',
  cssrs_moderate: 'C-SSRS moderate risk',
};

function truncate(s, n) {
  const str = String(s || '');
  return str.length > n ? `${str.slice(0, n - 1)}…` : str;
}

/** data() of a snapshot-like, or null when absent / deleted. */
function dataOf(snap) {
  if (!snap || snap.exists === false) return null;
  const d = typeof snap.data === 'function' ? snap.data() : null;
  return d || null;
}

function param(ctx, name, snap) {
  const p = ctx && ctx.params && ctx.params[name];
  if (typeof p === 'string' && p) return p;
  return snap && snap.id;
}

function isTooOld(ctx, maxAgeMs, now = Date.now()) {
  const t = ctx && ctx.eventTime;
  return typeof t === 'number' && Number.isFinite(t) && now - t > maxAgeMs;
}

/**
 * @param {import('./deps').CoreDeps} deps
 * @param {{sendPushToUser: Function}} push
 */
function createTriggers({ db, FieldValue, Timestamp, logger }, push) {
  const { sendPushToUser } = push;

  /**
   * Creates crisis_events/{crisisId}, or — if it already exists (a retry, or the
   * patient app wrote the same deterministic id first, e.g. the immediate
   * on-device PHQ-9 alert) — merges server-verified facts without ever throwing
   * on the conflict and without touching
   * acknowledged/acknowledgedAt/acknowledgedBy/timestamp. Severity only escalates.
   * The push is sent exactly once by crisisEventCreated regardless of creator.
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
  async function vitalCreated(snap, ctx) {
    const raw = dataOf(snap);
    if (!raw) return { status: 'no-data' };
    // 5-minute aggregate windows don't alert: out-of-range samples are written
    // separately as `immediate` docs. Skipping before any read keeps the free
    // tier's read/write budget (see docs/DATA_MODEL.md "Free-tier budget").
    if (vitals.skipVitalTrigger(raw)) return { status: 'aggregate-skipped' };
    const vitalId = param(ctx, 'vitalId', snap);
    const check = vitals.validateVitalReading(raw);
    if (!check.ok) {
      const log = check.sensorError ? logger.warn : logger.error;
      log(check.sensorError ? 'vital rejected as sensor error (no alert)' : 'invalid vital document',
        { vitalId, patientId: raw.patientId, type: raw.type, reason: check.reason });
      return { status: 'invalid' };
    }
    const reading = check.reading;
    const spec = vitals.VITAL_SPECS[reading.type];
    const userRef = db().collection(COLLECTIONS.USERS).doc(reading.patientId);
    const cooldownRef = db().collection(COLLECTIONS.ALERT_COOLDOWNS).doc(reading.patientId);
    const crisisId = vitals.crisisIdForVital(vitalId);
    const crisisRef = db().collection(COLLECTIONS.CRISIS_EVENTS).doc(crisisId);

    const outcome = await db().runTransaction(async (tx) => {
      const [userSnap, cdSnap, crisisSnap] = await tx.getAll(userRef, cooldownRef, crisisRef);
      if (!userSnap.exists) return { status: 'no-user', warnings: [] };

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
      return { status: outcome.status };
    }
    for (const w of outcome.warnings) {
      logger.warn('invalid vitalThresholds override', { patientId: reading.patientId, warning: w });
    }
    if (outcome.status === 'alerted-unassigned') logUnassigned(reading.patientId, crisisId);
    logger.info('vital processed', {
      vitalId, patientId: reading.patientId, type: reading.type, status: outcome.status,
    });
    return { status: outcome.status, crisisId };
  }

  async function raiseClinicalCrisis(source, docId, data, evaluation) {
    const patientId = data && data.patientId;
    if (typeof patientId !== 'string' || !patientId) {
      logger.error(`${source} without patientId; cannot raise crisis`, { docId });
      return { status: 'no-patient' };
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
    return { status: outcome, crisisId };
  }

  /** daily_logs/{logId} created: riskScore >= 75 => high_risk crisis. */
  async function dailyLogCreated(snap, ctx) {
    const data = dataOf(snap);
    if (!data) return { status: 'no-data' };
    const evaluation = clinical.evaluateDailyLog(data);
    if (!evaluation) return { status: 'normal' };
    return raiseClinicalCrisis('daily_log', param(ctx, 'logId', snap), data, evaluation);
  }

  /**
   * daily_logs/{logId} updated. The patient app merges ML results (mlRisk.riskScore,
   * a recomputed riskScore) into the log AFTER creating it, so a crisis-level
   * score may only appear on update. Same deterministic crisis id => no duplicate.
   */
  async function dailyLogUpdated(change, ctx) {
    const before = dataOf(change && change.before);
    const after = dataOf(change && change.after);
    if (!after) return { status: 'no-data' };
    const prevRisk = before ? clinical.extractRiskScore(before) : null;
    const nextRisk = clinical.extractRiskScore(after);
    if (nextRisk === null || (prevRisk !== null && nextRisk <= prevRisk)) return { status: 'unchanged' };
    const evaluation = clinical.evaluateDailyLog(after);
    if (!evaluation) return { status: 'normal' };
    return raiseClinicalCrisis('daily_log', param(ctx, 'logId', change.after), after, evaluation);
  }

  /** clinical_assessments/{assessmentId} created: PHQ-9 >= 20, item 9 > 0, risk >= 75. */
  async function assessmentCreated(snap, ctx) {
    const data = dataOf(snap);
    if (!data) return { status: 'no-data' };
    const assessmentId = param(ctx, 'assessmentId', snap);
    const phq = clinical.extractPhq9(data);
    if (phq.total === null && phq.item9 === null && /phq/i.test(String(data.type || ''))) {
      logger.error('PHQ assessment without readable score/items; cannot screen for crisis',
        { assessmentId, patientId: data.patientId });
    }
    const evaluation = clinical.evaluateAssessment(data);
    if (!evaluation) return { status: 'normal' };
    return raiseClinicalCrisis('assessment', assessmentId, data, evaluation);
  }

  /** crisis_events/{eventId} created: high-priority push to the therapist. */
  async function crisisEventCreated(snap, ctx) {
    const c = dataOf(snap);
    if (!c) return { status: 'no-data' };
    const eventId = param(ctx, 'eventId', snap);
    const patientId = c.patientId;
    if (typeof patientId !== 'string' || !patientId) {
      logger.error('crisis event without patientId', { eventId });
      return { status: 'no-patient' };
    }
    // Prefer the patient's CURRENT therapist (authoritative) over the stamp.
    const userSnap = await db().collection(COLLECTIONS.USERS).doc(patientId).get();
    const therapistId = (userSnap.exists && userSnap.get('therapistId')) || c.therapistId;
    if (!therapistId) {
      logger.error('CRISIS EVENT HAS NO THERAPIST — push not sent', { eventId, patientId });
      return { status: 'no-therapist' };
    }
    const patientName = c.patientName || (userSnap.exists && userSnap.get('name')) || 'Patient';
    const prefix = c.severity === 'critical' ? 'URGENT: ' : '';
    const title = truncate(c.title || `${prefix}${DEFAULT_CRISIS_TITLES[c.eventType] || 'Alert'}: ${patientName}`, 120);
    const body = truncate(c.message || `${patientName} needs attention. Open MindTwin now.`, 240);
    const result = await sendPushToUser({
      uid: therapistId,
      app: 'therapist',
      channelId: CHANNELS.CLINICAL_CRITICAL,
      title,
      body,
      data: { type: PUSH_TYPES.CRISIS, eventId, patientId },
      receiptKey: `crisis_${eventId}`,
    });
    logger.info('crisis push', { eventId, therapistId, ...result });
    return { status: result.skipped ? 'skipped' : 'pushed', ...result };
  }

  /** chats/{chatId}/messages/{messageId} created: push to receiverId. */
  async function messageCreated(snap, ctx) {
    const m = dataOf(snap);
    if (!m) return { status: 'no-data' };
    const chatId = ctx && ctx.params && ctx.params.chatId;
    const messageId = param(ctx, 'messageId', snap);
    if (typeof chatId !== 'string' || !chatId) {
      logger.error('message without chat id', { messageId });
      return { status: 'invalid' };
    }
    if (isTooOld(ctx, MAX_NON_CRITICAL_AGE_MS)) {
      logger.warn('dropping stale chat push', { chatId, messageId });
      return { status: 'stale' };
    }
    const participants = String(chatId).split('__');
    if (participants.length !== 2 ||
        !participants.includes(m.senderId) ||
        !participants.includes(m.receiverId) ||
        m.senderId === m.receiverId) {
      logger.error('message sender/receiver do not match chat id', { chatId, messageId });
      return { status: 'invalid' };
    }
    // Privacy: message text is NOT put in the push (lock screens are visible
    // to others; this is mental-health content).
    const senderName = truncate(m.senderName || 'MindTwin', 60);
    const result = await sendPushToUser({
      uid: m.receiverId,
      app: null,
      channelId: CHANNELS.CHAT_MESSAGES,
      title: `New message from ${senderName}`,
      body: 'Open MindTwin to read it.',
      data: { type: PUSH_TYPES.CHAT, chatId, senderId: m.senderId, senderName },
      receiptKey: `msg_${chatId}_${messageId}`,
    });
    return { status: result.skipped ? 'skipped' : 'pushed', ...result };
  }

  /**
   * Server-side double-booking guard: clients check overlaps too, but two
   * concurrent writes can race. Flags `conflict` / `conflictWith` on the
   * appointment (server-only fields) and alerts the therapist once.
   */
  async function checkDoubleBooking(eventId, appointmentId, after) {
    const start = toMillis(after.scheduledAt);
    const windowStart = Timestamp.fromMillis(start - MAX_DURATION_MIN * 60 * 1000);
    const windowEnd = Timestamp.fromMillis(start + 24 * 60 * 60 * 1000);
    const snap = await db().collection(COLLECTIONS.APPOINTMENTS)
      .where('therapistId', '==', after.therapistId)
      .where('status', '==', 'scheduled')
      .where('scheduledAt', '>=', windowStart)
      .where('scheduledAt', '<', windowEnd)
      .get();
    const others = snap.docs.map((d) => ({
      id: d.id, scheduledAt: d.get('scheduledAt'), durationMinutes: d.get('durationMinutes'),
    }));
    const overlaps = findOverlaps(appointmentId, after, others);
    const conflict = overlaps.length > 0;
    const prevIds = Array.isArray(after.conflictWith) ? [...after.conflictWith].sort() : [];
    if (after.conflict !== conflict || prevIds.join(',') !== overlaps.join(',')) {
      await db().collection(COLLECTIONS.APPOINTMENTS).doc(appointmentId)
        .update({ conflict, conflictWith: overlaps });
    }
    if (conflict) {
      logger.warn('appointment double booking detected', { appointmentId, overlaps });
      await sendPushToUser({
        uid: after.therapistId,
        app: 'therapist',
        channelId: CHANNELS.APPOINTMENTS,
        title: 'Possible double booking',
        body: 'An appointment overlaps another scheduled appointment. Please review.',
        data: { type: PUSH_TYPES.APPOINTMENT, appointmentId },
        receiptKey: `apptconflict_${eventId}`,
      });
    }
    return overlaps;
  }

  /** appointments/{appointmentId} written: meeting link + push other party. */
  async function appointmentWritten(change, ctx) {
    const before = dataOf(change && change.before);
    const after = dataOf(change && change.after);
    const appointmentId = param(ctx, 'appointmentId', (change && (change.after || change.before)));
    const eventId = ctx && ctx.eventId;
    if (typeof eventId !== 'string' || !eventId) {
      throw new Error('appointmentWritten requires a deterministic ctx.eventId');
    }
    const plan = planAppointmentEffects(before, after);
    const effects = { meetingUrl: false, conflicts: null, pushed: [] };

    if (plan.setMeetingUrl) {
      const ref = db().collection(COLLECTIONS.APPOINTMENTS).doc(appointmentId);
      effects.meetingUrl = await db().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) return false;
        const d = snap.data();
        // Only set once; never overwrite an existing link.
        if (d.status !== 'scheduled' || d.isVirtual !== true || d.meetingUrl) return false;
        tx.update(ref, {
          meetingUrl: buildMeetingUrl(appointmentId),
          meetingUrlCreatedAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
    }

    if (needsConflictCheck(before, after)) {
      effects.conflicts = await checkDoubleBooking(eventId, appointmentId, after);
    }

    if (!plan.recipients.length) return effects;
    if (isTooOld(ctx, MAX_NON_CRITICAL_AGE_MS)) {
      logger.warn('dropping stale appointment push', { appointmentId });
      return effects;
    }
    for (const who of plan.recipients) {
      const uid = who === 'patient' ? after.patientId : after.therapistId;
      if (!uid) continue;
      await sendPushToUser({
        uid,
        app: who,
        channelId: CHANNELS.APPOINTMENTS,
        title: plan.title,
        body: plan.body,
        data: { type: PUSH_TYPES.APPOINTMENT, appointmentId },
        receiptKey: `appt_${eventId}_${who}`,
      });
      effects.pushed.push(who);
    }
    return effects;
  }

  /**
   * Account lifecycle cleanup after a Firebase Auth account was deleted.
   * Removes the personal profile, push tokens and alert cooldowns. Clinical
   * records (daily_logs, clinical_assessments, crisis_events, vitals,
   * journal_entries, appointments) are intentionally RETAINED: health-record
   * retention obligations apply. Erasure goes through the clinic's documented
   * data-deletion process, not automation.
   */
  async function cleanupDeletedUser(uid) {
    const firestore = db();
    const tokens = await firestore.collection(COLLECTIONS.FCM_TOKENS).where('uid', '==', uid).get();
    const batch = firestore.batch();
    tokens.forEach((doc) => batch.delete(doc.ref));
    batch.delete(firestore.collection(COLLECTIONS.USERS).doc(uid));
    batch.delete(firestore.collection(COLLECTIONS.ALERT_COOLDOWNS).doc(uid));
    await batch.commit();
    logger.info('Deleted account cleanup complete', { uid, tokensRemoved: tokens.size });
    return { tokensRemoved: tokens.size };
  }

  return {
    vitalCreated,
    dailyLogCreated,
    dailyLogUpdated,
    assessmentCreated,
    crisisEventCreated,
    messageCreated,
    appointmentWritten,
    cleanupDeletedUser,
    createOrMergeCrisis,
  };
}

module.exports = { createTriggers, MAX_NON_CRITICAL_AGE_MS, isTooOld, dataOf };
