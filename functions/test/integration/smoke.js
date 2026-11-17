'use strict';

/**
 * End-to-end smoke test against the local emulators (auth, firestore, functions).
 * From the repo root:
 *   firebase emulators:exec --only auth,firestore,functions --project demo-mindtwin \
 *     "node functions/test/integration/smoke.js"
 * Never point this at a real project: it refuses to run without emulator env vars.
 */

const assert = require('node:assert/strict');
const path = require('node:path');
const { createRequire } = require('node:module');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('Refusing to run: emulator environment variables are not set.');
  process.exit(2);
}

const fnRequire = createRequire(path.join(__dirname, '..', '..', 'package.json'));
const { initializeApp } = fnRequire('firebase-admin/app');
const { getFirestore, Timestamp } = fnRequire('firebase-admin/firestore');
const { getAuth } = fnRequire('firebase-admin/auth');

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-mindtwin';
initializeApp({ projectId: PROJECT });
const db = getFirestore();
const auth = getAuth();
const FN_BASE = `http://${process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001'}/${PROJECT}/us-central1`;
const AUTH_BASE = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(fn, label, timeoutMs = 20000) {
  const start = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - start > timeoutMs) throw new Error(`timeout waiting for ${label}`);
    await sleep(250);
  }
}
const docExists = (p) => async () => ((await db.doc(p).get()).exists ? (await db.doc(p).get()).data() : null);

async function idToken(email) {
  const res = await fetch(`${AUTH_BASE}/accounts:signInWithPassword?key=fake`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password: 'secret123', returnSecureToken: true }),
  });
  return (await res.json()).idToken;
}
async function call(name, email, data) {
  const res = await fetch(`${FN_BASE}/${name}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${await idToken(email)}` },
    body: JSON.stringify({ data }),
  });
  return res.json();
}

async function main() {
  // ---- callables: therapist signup -> admin approval -> patient registration
  const admin = await auth.createUser({ email: 'admin@x.test', password: 'secret123' });
  await auth.setCustomUserClaims(admin.uid, { admin: true });
  const t = await auth.createUser({ email: 'ther@x.test', password: 'secret123' });
  const p = await auth.createUser({ email: 'pat@x.test', password: 'secret123' });

  let r = await call('registerTherapist', 'ther@x.test', { name: 'Dr Smoke', licenseNumber: 'L-1' });
  assert.deepEqual(r.result, { status: 'pending' }, JSON.stringify(r));
  r = await call('getMyInviteCode', 'ther@x.test', {});
  assert.equal(r.error && r.error.status, 'PERMISSION_DENIED', 'pending therapist has no code');
  r = await call('approveTherapist', 'pat@x.test', { therapistUid: t.uid });
  assert.equal(r.error && r.error.status, 'PERMISSION_DENIED', 'non-admin cannot approve');
  r = await call('approveTherapist', 'admin@x.test', { therapistUid: t.uid });
  const code = r.result && r.result.inviteCode;
  assert.match(code, /^[A-Z2-9]{8}$/, JSON.stringify(r));
  assert.equal((await auth.getUser(t.uid)).customClaims.role, 'therapist');
  r = await call('getMyInviteCode', 'ther@x.test', {});
  assert.equal(r.result.inviteCode, code, 'stable invite code');

  r = await call('registerPatient', 'pat@x.test', { name: 'Pat Smoke', inviteCode: 'ZZZZ2222' });
  assert.equal(r.error && r.error.status, 'NOT_FOUND');
  r = await call('registerPatient', 'pat@x.test', { name: '', inviteCode: code });
  assert.equal(r.error && r.error.status, 'INVALID_ARGUMENT');
  r = await call('registerPatient', 'pat@x.test', { name: 'Pat Smoke', inviteCode: code.toLowerCase() });
  assert.deepEqual(r.result, { therapistId: t.uid, therapistName: 'Dr Smoke' }, JSON.stringify(r));
  assert.equal((await auth.getUser(p.uid)).customClaims.role, 'patient');
  const pdoc = (await db.doc(`users/${p.uid}`).get()).data();
  assert.equal(pdoc.role, 'patient');
  assert.equal(pdoc.therapistId, t.uid);
  r = await call('registerTherapist', 'pat@x.test', { name: 'Sneaky' });
  assert.equal(r.error && r.error.status, 'FAILED_PRECONDITION');
  console.log('callables OK');

  // ---- vitals
  const pid = p.uid;
  const now = Date.now();
  const v1 = `${pid}_heart_rate_${now}`;
  await db.doc(`vitals/${v1}`).set({
    patientId: pid, therapistId: t.uid, type: 'heart_rate', value: 130, unit: 'bpm',
    measuredAt: Timestamp.fromMillis(now), source: 'wear_os', createdAt: Timestamp.now(),
  });
  const c1 = await waitFor(docExists(`crisis_events/vital_${v1}`), 'vital crisis');
  assert.equal(c1.eventType, 'vital_high');
  assert.equal(c1.therapistId, t.uid);
  assert.equal(c1.vital.threshold, 120);
  await waitFor(async () => {
    const u = (await db.doc(`users/${pid}`).get()).data();
    return u.latestVitals && u.latestVitals.heartRate && u.latestVitals.heartRate.value === 130;
  }, 'latestVitals');
  await waitFor(docExists(`push_receipts/crisis_vital_${v1}`), 'crisis push receipt');

  const v2 = `${pid}_heart_rate_${now + 1000}`;
  const v3 = `${pid}_heart_rate_${now + 2000}`;
  await db.doc(`vitals/${v2}`).set({
    patientId: pid, therapistId: t.uid, type: 'heart_rate', value: 140, unit: 'bpm',
    measuredAt: Timestamp.fromMillis(now + 1000), source: 'wear_os', createdAt: Timestamp.now(),
  });
  await db.doc(`vitals/${v3}`).set({
    patientId: pid, therapistId: t.uid, type: 'heart_rate', value: 0, unit: 'bpm',
    measuredAt: Timestamp.fromMillis(now + 2000), source: 'wear_os', createdAt: Timestamp.now(),
  });
  await waitFor(async () => {
    const u = (await db.doc(`users/${pid}`).get()).data();
    return u.latestVitals.heartRate.value === 140;
  }, 'latestVitals advanced');
  await sleep(3000);
  assert.equal((await db.doc(`crisis_events/vital_${v2}`).get()).exists, false, 'cooldown suppresses');
  assert.equal((await db.doc(`crisis_events/vital_${v3}`).get()).exists, false, 'sensor error ignored');
  assert.equal((await db.doc(`users/${pid}`).get()).data().latestVitals.heartRate.value, 140,
    'sensor error not written to snapshot');
  console.log('vitals OK');

  // ---- daily log + assessment
  const log = await db.collection('daily_logs').add({
    patientId: pid, therapistId: t.uid, timestamp: Timestamp.now(), riskScore: 80,
  });
  const c2 = await waitFor(docExists(`crisis_events/dailylog_${log.id}`), 'daily log crisis');
  assert.equal(c2.eventType, 'high_risk');
  const low = await db.collection('daily_logs').add({
    patientId: pid, therapistId: t.uid, timestamp: Timestamp.now(), riskScore: 30,
  });
  await low.set({ mlRisk: { riskScore: 85 } }, { merge: true });
  await waitFor(docExists(`crisis_events/dailylog_${low.id}`), 'ML-updated daily log crisis');

  const a = await db.collection('clinical_assessments').add({
    patientId: pid, therapistId: t.uid, timestamp: Timestamp.now(), type: 'phq9_gad7',
    phq9Score: 1, gad7Score: 0, answers: { phq9: [0, 0, 0, 0, 0, 0, 0, 0, 1], gad7: [0, 0, 0, 0, 0, 0, 0] },
  });
  const c3 = await waitFor(docExists(`crisis_events/assessment_${a.id}`), 'assessment crisis');
  assert.equal(c3.severity, 'critical');
  assert.equal(c3.eventType, 'phq9_severe');
  console.log('clinical OK');

  // ---- patient app creates crisis_events/assessment_<id> FIRST (immediate
  // item-9 alert), therapist acknowledges, then the assessment syncs.
  const aRef = db.collection('clinical_assessments').doc();
  const pcId = `assessment_${aRef.id}`;
  await db.doc(`crisis_events/${pcId}`).set({
    patientId: pid, therapistId: t.uid, patientName: 'Pat Smoke', eventType: 'phq9_severe',
    severity: 'high', title: 'PHQ-9 alert', message: 'item 9', acknowledged: false,
    timestamp: Timestamp.now(), details: { assessmentId: aRef.id, item9: 1 },
  });
  await waitFor(docExists(`push_receipts/crisis_${pcId}`), 'push for patient-created phq9 crisis');
  await db.doc(`crisis_events/${pcId}`).update({
    acknowledged: true, acknowledgedAt: Timestamp.now(), acknowledgedBy: t.uid,
  });
  await aRef.set({
    patientId: pid, therapistId: t.uid, timestamp: Timestamp.now(), type: 'phq9_gad7',
    totalScore: 22, item9: 2, phq9Answers: [3, 3, 3, 3, 3, 3, 2, 0, 2],
  });
  const merged = await waitFor(async () => {
    const d = (await db.doc(`crisis_events/${pcId}`).get()).data();
    return d.serverVerified && d.serverVerified.item9 === 2 ? d : null;
  }, 'server-verified merge');
  assert.equal(merged.acknowledged, true, 'acknowledgement preserved');
  assert.equal(merged.acknowledgedBy, t.uid);
  assert.equal(merged.severity, 'critical', 'severity escalated');
  assert.equal(merged.serverVerified.totalScore, 22);
  const receipts = await db.collection('push_receipts').where('__name__', '>=', `crisis_${pcId}`)
    .where('__name__', '<=', `crisis_${pcId}\uf8ff`).get();
  assert.equal(receipts.size, 1, 'exactly one push receipt');
  assert.equal(receipts.docs[0].get('attempts'), 1, 'push attempted once');
  const dupes = await db.collection('crisis_events').where('sourceId', '==', aRef.id).get();
  assert.equal(dupes.size, 0, 'function did not create a second crisis doc');

  // ---- function FIRST: assessment synced before the client alert
  const bRef = db.collection('clinical_assessments').doc();
  await bRef.set({
    patientId: pid, therapistId: t.uid, timestamp: Timestamp.now(), type: 'phq9_gad7',
    totalScore: 3, item9: 1, phq9Answers: [0, 0, 1, 0, 0, 0, 1, 0, 1],
  });
  const fc = await waitFor(docExists(`crisis_events/assessment_${bRef.id}`), 'function-created phq9 crisis');
  assert.equal(fc.severity, 'critical');
  await waitFor(docExists(`push_receipts/crisis_assessment_${bRef.id}`), 'push once');
  console.log('phq9 dedupe OK');

  // ---- appointments
  const start = Timestamp.fromMillis(Date.now() + 86400000);
  const ap = await db.collection('appointments').add({
    patientId: pid, therapistId: t.uid, requestedBy: 'therapist', status: 'scheduled',
    scheduledAt: start, proposedAt: null, durationMinutes: 60, isVirtual: true, meetingUrl: null,
    createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  });
  const apd = await waitFor(async () => {
    const d = (await ap.get()).data();
    return d.meetingUrl ? d : null;
  }, 'meetingUrl');
  assert.match(apd.meetingUrl, new RegExp(`^https://meet\\.jit\\.si/MindTwin-${ap.id}-[a-z2-9]{10}$`));
  const ap2 = await db.collection('appointments').add({
    patientId: pid, therapistId: t.uid, requestedBy: 'therapist', status: 'scheduled',
    scheduledAt: Timestamp.fromMillis(start.toMillis() + 30 * 60000), proposedAt: null,
    durationMinutes: 30, isVirtual: false, meetingUrl: null,
    createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  });
  await waitFor(async () => (await ap2.get()).data().conflict === true, 'double booking flag');
  const url1 = apd.meetingUrl;
  await ap.update({ notes: 'x', updatedAt: Timestamp.now() });
  await sleep(2000);
  assert.equal((await ap.get()).data().meetingUrl, url1, 'meetingUrl set only once');
  console.log('appointments OK');

  // ---- joinTherapist restamps history
  const t2 = await auth.createUser({ email: 'ther2@x.test', password: 'secret123' });
  await call('registerTherapist', 'ther2@x.test', { name: 'Dr Two' });
  const code2 = (await call('approveTherapist', 'admin@x.test', { therapistUid: t2.uid })).result.inviteCode;
  r = await call('joinTherapist', 'pat@x.test', { inviteCode: code2 });
  assert.equal(r.result.therapistId, t2.uid, JSON.stringify(r));
  await db.collection('journal_entries').add({
    patientId: pid, therapistId: t.uid, source: 'voice_journal', text: 'j', createdAt: Timestamp.now(),
  });
  r = await call('joinTherapist', 'pat@x.test', { inviteCode: code2 });
  assert.equal(r.result.therapistId, t2.uid, 'idempotent re-join');
  const journal = await db.collection('journal_entries').where('patientId', '==', pid).get();
  assert.ok(journal.size > 0 && journal.docs.every((d) => d.get('therapistId') === t2.uid), 'journal restamped');
  const logs = await db.collection('daily_logs').where('patientId', '==', pid).get();
  assert.ok(logs.docs.every((d) => d.get('therapistId') === t2.uid), 'history restamped');
  console.log('joinTherapist OK');
  console.log('SMOKE PASSED');
}

main().then(() => process.exit(0)).catch((err) => {
  console.error('SMOKE FAILED:', err);
  process.exit(1);
});
