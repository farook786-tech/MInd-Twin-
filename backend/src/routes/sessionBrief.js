'use strict';

/**
 * POST /api/brief/:patientId — pre-session brief for the patient's assigned
 * therapist.
 *
 * Request:  Authorization: Bearer <Firebase ID token>
 *           body (optional) {tzOffsetMinutes: number}  (minutes east of UTC, for day boundaries / dates)
 * Response: 200 {brief, narrative: string|null, narrativeReason: string|null}
 *           <status> {error: {code, message}} (same envelope as /api/callable)
 *
 * Access: ID token verified with checkRevoked=true; custom claim
 * role == 'therapist' AND users/{patientId}.therapistId == caller uid.
 * Reads use the Admin SDK with small, bounded queries (Spark quota):
 * worst case ~ 1 + 100 + 60 + 10 + 120 + 50 + 20 + 14 (+300 raw vitals) docs.
 * Nothing is written. Brief content is never logged.
 */

const express = require('express');
const TokenBucketMiddleware = require('../middleware/TokenBucketMiddleware');
const { getFirebaseAdmin } = require('../services/FirebaseAdmin');
const {
  buildSessionBrief, choosePeriod, localDateKey, DAY_MS,
} = require('../services/SessionBriefBuilder');
const { generateNarrative, LLM_JOURNAL_EXCERPT_CHARS } = require('../services/SessionBriefNarrative');

const LIMITS = Object.freeze({
  appointments: 100,
  assessments: 60,
  priorAssessments: 10,
  dailyLogs: 120,
  crisisEvents: 50,
  journalEntries: 20,
  vitalsDailyDays: 14,
  vitals: 300,
});

const PATIENT_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

const AUTH_REJECT = new Set([
  'auth/id-token-expired',
  'auth/id-token-revoked',
  'auth/user-disabled',
  'auth/user-not-found',
  'auth/argument-error',
  'auth/invalid-id-token',
  'auth/invalid-argument',
]);

const STATUS = { 'invalid-argument': 400, unauthenticated: 401, 'permission-denied': 403, 'resource-exhausted': 429, internal: 500, unavailable: 503 };

function sendError(res, code, message) {
  res.status(STATUS[code] || 500).json({ error: { code, message } });
}

function docs(snap) {
  return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
}

/**
 * Bounded Admin-SDK reads. Every query uses an index already declared in
 * firestore.indexes.json (or equality-only filters, which need none).
 */
async function loadBriefData(db, { patientId, therapistId, nowMs, tzOffsetMinutes }) {
  const truncated = [];
  const note = (name, arr, limit) => {
    if (arr.length >= limit) truncated.push(name);
    return arr;
  };

  const appointments = note('appointments', docs(await db.collection('appointments')
    .where('patientId', '==', patientId)
    .where('therapistId', '==', therapistId)
    .limit(LIMITS.appointments)
    .get()), LIMITS.appointments);

  const period = choosePeriod({ nowMs, appointments, therapistId });
  const from = new Date(period.fromMs);
  const logsFrom = new Date(Math.min(period.fromMs, nowMs - 30 * DAY_MS)); // streak context

  const vitalsDays = Math.min(LIMITS.vitalsDailyDays, Math.ceil((nowMs - period.fromMs) / DAY_MS) + 1);
  const vitalsDailyRefs = [];
  for (let i = 0; i < vitalsDays; i += 1) {
    vitalsDailyRefs.push(db.collection('vitals_daily').doc(`${patientId}_${localDateKey(nowMs - i * DAY_MS, tzOffsetMinutes)}`));
  }

  const [assessSnap, priorSnap, logsSnap, eventsSnap, journalSnap, dailySnaps] = await Promise.all([
    db.collection('clinical_assessments')
      .where('patientId', '==', patientId)
      .where('timestamp', '>=', from)
      .orderBy('timestamp', 'asc')
      .limit(LIMITS.assessments)
      .get(),
    db.collection('clinical_assessments')
      .where('patientId', '==', patientId)
      .where('timestamp', '<', from)
      .orderBy('timestamp', 'desc')
      .limit(LIMITS.priorAssessments)
      .get(),
    db.collection('daily_logs')
      .where('patientId', '==', patientId)
      .where('timestamp', '>=', logsFrom)
      .orderBy('timestamp', 'desc')
      .limit(LIMITS.dailyLogs)
      .get(),
    db.collection('crisis_events')
      .where('patientId', '==', patientId)
      .orderBy('timestamp', 'desc')
      .limit(LIMITS.crisisEvents)
      .get(),
    // Only entries shared with THIS therapist.
    db.collection('journal_entries')
      .where('patientId', '==', patientId)
      .where('therapistId', '==', therapistId)
      .orderBy('createdAt', 'desc')
      .limit(LIMITS.journalEntries)
      .get(),
    vitalsDailyRefs.length ? db.getAll(...vitalsDailyRefs) : Promise.resolve([]),
  ]);

  const vitalsDaily = dailySnaps.filter((s) => s.exists).map((s) => ({ id: s.id, data: s.data() }));
  let vitals = [];
  if (vitalsDaily.length === 0) {
    const rawFrom = new Date(Math.max(period.fromMs, nowMs - LIMITS.vitalsDailyDays * DAY_MS));
    vitals = note('vitals', docs(await db.collection('vitals')
      .where('patientId', '==', patientId)
      .where('measuredAt', '>=', rawFrom)
      .orderBy('measuredAt', 'desc')
      .limit(LIMITS.vitals)
      .get()), LIMITS.vitals);
  }

  return {
    period,
    appointments,
    assessments: note('clinical_assessments', docs(assessSnap), LIMITS.assessments),
    priorAssessments: docs(priorSnap),
    dailyLogs: note('daily_logs', docs(logsSnap), LIMITS.dailyLogs),
    crisisEvents: docs(eventsSnap),
    journalEntries: docs(journalSnap),
    vitalsDaily,
    vitals,
    truncated,
  };
}

/**
 * @param {object} [deps] injectable for tests
 * @param {() => ({verifyIdToken(t: string, checkRevoked: boolean): Promise<object>})|null} [deps.getAuth]
 * @param {(patientId: string) => Promise<object|null>} [deps.readPatient] users/{patientId} data or null
 * @param {(args: object) => Promise<object>} [deps.loadData]
 * @param {Function} [deps.callLlm]
 * @param {object} [deps.env]
 * @param {() => number} [deps.now]
 * @param {{capacity: number, windowMs: number}} [deps.perUid]
 */
function createSessionBriefRouter(deps = {}) {
  const getAdmin = deps.getAdmin || getFirebaseAdmin;
  const getAuth = deps.getAuth || (() => {
    const admin = getAdmin();
    return admin ? admin.auth() : null;
  });
  const readPatient = deps.readPatient || (async (patientId) => {
    const admin = getAdmin();
    const snap = await admin.firestore().collection('users').doc(patientId).get();
    return snap.exists ? snap.data() : null;
  });
  const loadData = deps.loadData || ((args) => loadBriefData(getAdmin().firestore(), args));
  const env = deps.env || process.env;
  const now = deps.now || (() => Date.now());
  const perUid = deps.perUid || { capacity: 10, windowMs: 10 * 60 * 1000 };

  const router = express.Router();
  const ipLimiter = TokenBucketMiddleware({ capacity: 30, windowMs: 60 * 1000, keyFn: (req) => `brief-ip:${req.ip}` });
  const uidLimiter = TokenBucketMiddleware({ ...perUid, keyFn: (req) => `brief-uid:${req.briefUid}` });
  const envelope429 = (limiter) => (req, res, next) => {
    const json = res.json.bind(res);
    res.json = (body) => (res.statusCode === 429 ?
      json({ error: { code: 'resource-exhausted', message: 'Too many brief requests. Please wait a few minutes.' } }) :
      json(body));
    limiter(req, res, (err) => {
      res.json = json;
      next(err);
    });
  };

  router.post('/:patientId', envelope429(ipLimiter), async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    const auth = getAuth();
    if (!auth) return sendError(res, 'unavailable', 'The MindTwin server is not connected to Firebase.');
    const m = /^Bearer\s+(\S+)$/i.exec(String(req.get('authorization') || ''));
    if (!m) return sendError(res, 'unauthenticated', 'Sign in first.');
    let decoded;
    try {
      decoded = await auth.verifyIdToken(m[1], true);
    } catch (err) {
      const code = err && (err.code || (err.errorInfo && err.errorInfo.code));
      if (code && AUTH_REJECT.has(code)) return sendError(res, 'unauthenticated', 'Your session expired. Please sign in again.');
      console.error('[SessionBrief] token verification failed:', code || 'error');
      return sendError(res, 'unavailable', 'Could not verify your sign-in right now. Please try again.');
    }
    if (decoded.role !== 'therapist') {
      return sendError(res, 'permission-denied', 'Only approved therapists can create a session brief.');
    }
    req.briefUid = decoded.uid;
    return next();
  }, envelope429(uidLimiter), async (req, res) => {
    const { patientId } = req.params;
    const uid = req.briefUid;
    if (!PATIENT_ID_RE.test(patientId)) return sendError(res, 'invalid-argument', 'Invalid patient id.');
    const tzRaw = req.body && typeof req.body === 'object' ? Number(req.body.tzOffsetMinutes) : 0;
    const tzOffsetMinutes = Number.isFinite(tzRaw) ? Math.max(-840, Math.min(840, Math.round(tzRaw))) : 0;

    try {
      const patient = await readPatient(patientId);
      // Same answer for "no such user" and "not your patient" (no enumeration).
      if (!patient || patient.therapistId !== uid) {
        console.warn('[SessionBrief] denied', JSON.stringify({ uid }));
        return sendError(res, 'permission-denied', 'This patient is not assigned to you.');
      }
      const nowMs = now();
      const data = await loadData({ patientId, therapistId: uid, nowMs, tzOffsetMinutes });
      const common = {
        nowMs,
        period: data.period,
        tzOffsetMinutes,
        patient: { ...patient, __id: patientId },
        assessments: data.assessments,
        priorAssessments: data.priorAssessments,
        dailyLogs: data.dailyLogs,
        crisisEvents: data.crisisEvents,
        journalEntries: data.journalEntries,
        vitalsDaily: data.vitalsDaily,
        vitals: data.vitals,
        appointments: data.appointments,
        truncated: data.truncated,
      };
      const brief = buildSessionBrief({ ...common, dateMode: 'absolute' });

      let narrative = null;
      let narrativeReason = null;
      try {
        const relativeBrief = buildSessionBrief({
          ...common, dateMode: 'relative', journalExcerptChars: LLM_JOURNAL_EXCERPT_CHARS,
        });
        const out = await generateNarrative({ relativeBrief, patient, env, callLlm: deps.callLlm });
        narrative = out.narrative;
        narrativeReason = out.reason;
      } catch (err) {
        narrativeReason = 'narrative_error';
        console.error('[SessionBrief] narrative failed:', err && err.message);
      }

      console.log('[SessionBrief] built', JSON.stringify({
        uid, sections: brief.sections.length, flags: brief.flags.length, narrative: narrative ? 'yes' : narrativeReason,
      }));
      return res.status(200).json({ brief, narrative, narrativeReason });
    } catch (err) {
      const code = err && err.code;
      // Firestore RESOURCE_EXHAUSTED (8) = Spark daily quota used up.
      if (code === 8 || code === 'resource-exhausted') {
        return sendError(res, 'unavailable', 'Daily database quota reached. Try again later.');
      }
      console.error('[SessionBrief] failed:', err && err.message);
      return sendError(res, 'internal', 'Could not build the brief. Please try again.');
    }
  });

  return router;
}

module.exports = { createSessionBriefRouter, loadBriefData, LIMITS };
