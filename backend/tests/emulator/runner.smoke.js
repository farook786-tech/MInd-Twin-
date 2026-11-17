'use strict';

/**
 * End-to-end smoke test of the free-plan stack against the Auth + Firestore
 * emulators: /api/callable (real ID-token verification) and the
 * listener-based trigger runner (two concurrent instances, restarts).
 *
 * Run from backend/:  npm run test:emulator
 * (= firebase emulators:exec --config tests/emulator/firebase.smoke.json
 *    --only auth,firestore --project demo-mindtwin "node tests/emulator/runner.smoke.js")
 * Refuses to run without emulator env vars. FCM is replaced by a counting fake.
 */

const assert = require('node:assert/strict');
const express = require('express');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('Refusing to run: emulator environment variables are not set.');
  process.exit(2);
}
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-mindtwin';
// Never pick up real credentials in this test.
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
delete process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON;

const { getFirebaseAdmin } = require('../../src/services/FirebaseAdmin');
const { setupFunctionsRunner, buildRunner } = require('../../src/firebase/functionsRunner');

const admin = getFirebaseAdmin();
const db = admin.firestore();
const auth = admin.auth();
const { Timestamp, FieldValue } = admin.firestore;
const AUTH_BASE = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(fn, label, timeoutMs = 20000) {
  const start = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - start > timeoutMs) throw new Error(`timeout waiting for ${label}`);
    await sleep(200);
  }
}
const getData = async (p) => {
  const s = await db.doc(p).get();
  return s.exists ? s.data() : null;
};

// ---- fake FCM shared by every runner instance: counts real sends ---------
const sends = [];
const fakeMessaging = {
  async sendEachForMulticast(msg) {
    sends.push({ tokens: msg.tokens, data: msg.data, channel: msg.android.notification.channelId });
    return {
      successCount: msg.tokens.length,
      failureCount: 0,
      responses: msg.tokens.map(() => ({ success: true })),
    };
  },
};
const sendsOfType = (type) => sends.filter((s) => s.data.type === type);

const quiet = { info: () => {}, warn: () => {}, error: (m, f) => console.error('[runner]', m, f || '') };
const runnerEnv = (id) => ({ RUNNER_INSTANCE_ID: id, RUNNER_FLUSH_MS: '500' });
function newRunner(id) {
  return buildRunner({ admin, env: runnerEnv(id), coreOverrides: { messaging: () => fakeMessaging }, logger: quiet }).runner;
}

async function idToken(email) {
  const res = await fetch(`${AUTH_BASE}/accounts:signInWithPassword?key=fake`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password: 'secret123', returnSecureToken: true }),
  });
  return (await res.json()).idToken;
}

async function main() {
  // ---------------------------------------------------------------- callables
  const app = express();
  app.use(express.json());
  const fr = setupFunctionsRunner(app, { env: { FUNCTIONS_RUNNER_ENABLED: 'false' } });
  const server = await new Promise((r) => { const s = app.listen(0, '127.0.0.1', () => r(s)); });
  const base = `http://127.0.0.1:${server.address().port}/api/callable`;
  const call = async (name, tokenOrEmail, data) => {
    const token = tokenOrEmail.includes('@') ? await idToken(tokenOrEmail) : tokenOrEmail;
    const res = await fetch(`${base}/${name}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
      body: JSON.stringify({ data }),
    });
    return { status: res.status, ...(await res.json()) };
  };

  const adminUser = await auth.createUser({ email: 'admin@x.test', password: 'secret123' });
  await auth.setCustomUserClaims(adminUser.uid, { admin: true });
  const t = await auth.createUser({ email: 'ther@x.test', password: 'secret123' });
  const p = await auth.createUser({ email: 'pat@x.test', password: 'secret123' });

  let r = await call('registerTherapist', 'ther@x.test', { name: 'Dr Smoke', licenseNumber: 'L-1' });
  assert.deepEqual(r, { status: 200, data: { status: 'pending' } });
  r = await call('getMyInviteCode', 'ther@x.test', {});
  assert.equal(r.status, 403, 'pending therapist has no code');
  assert.equal(r.error.code, 'permission-denied');
  r = await call('approveTherapist', 'pat@x.test', { therapistUid: t.uid });
  assert.equal(r.status, 403, 'non-admin cannot approve');
  r = await call('approveTherapist', 'admin@x.test', { therapistUid: t.uid });
  const code = r.data && r.data.inviteCode;
  assert.match(code, /^[A-Z2-9]{8}$/, JSON.stringify(r));
  assert.equal((await auth.getUser(t.uid)).customClaims.role, 'therapist');
  r = await call('getMyInviteCode', 'ther@x.test', {});
  assert.equal(r.data.inviteCode, code, 'stable invite code');
  r = await call('registerPatient', 'pat@x.test', { name: 'Pat Smoke', inviteCode: 'ZZZZ2222' });
  assert.equal(r.status, 404);
  assert.equal(r.error.code, 'not-found');
  r = await call('registerPatient', 'pat@x.test', { name: '', inviteCode: code });
  assert.equal(r.status, 400);
  r = await call('registerPatient', 'pat@x.test', { name: 'Pat Smoke', inviteCode: code.toLowerCase() });
  assert.deepEqual(r.data, { therapistId: t.uid, therapistName: 'Dr Smoke' }, JSON.stringify(r));
  assert.equal((await auth.getUser(p.uid)).customClaims.role, 'patient');
  r = await call('getMyInviteCode', 'garbage-token', {});
  assert.equal(r.status, 401);
  // Revoked sessions are refused (checkRevoked=true).
  const stale = await idToken('pat@x.test');
  await sleep(1100);
  await auth.revokeRefreshTokens(p.uid);
  r = await call('joinTherapist', stale, { inviteCode: code });
  assert.equal(r.status, 401, `revoked token must be refused: ${JSON.stringify(r)}`);
  console.log('callables over HTTP: OK');

  // ----------------------------------------------------- triggers (runner)
  await db.doc('fcm_tokens/tokT').set({ uid: t.uid, platform: 'android', app: 'therapist', updatedAt: Timestamp.now() });
  await db.doc('fcm_tokens/tokP').set({ uid: p.uid, platform: 'android', app: 'patient', updatedAt: Timestamp.now() });

  // Two instances at once (laptop + Render): must not double-send.
  let a = newRunner('smokeA');
  let b = newRunner('smokeB');
  await Promise.all([a.start(), b.start()]);
  await sleep(1500);

  const vitalId = `${p.uid}_heart_rate_${Date.now()}`;
  await db.doc(`vitals/${vitalId}`).set({
    patientId: p.uid, therapistId: t.uid, type: 'heart_rate', value: 150, unit: 'bpm',
    measuredAt: Timestamp.now(), source: 'wear_os', createdAt: FieldValue.serverTimestamp(),
  });
  const crisis = await waitFor(() => getData(`crisis_events/vital_${vitalId}`), 'vital crisis');
  assert.equal(crisis.eventType, 'vital_high');
  assert.equal(crisis.therapistId, t.uid);
  const receipt = await waitFor(async () => {
    const d = await getData(`push_receipts/crisis_vital_${vitalId}`);
    return d && d.status === 'sent' ? d : null;
  }, 'crisis push receipt');
  assert.equal(receipt.success, 1);
  await sleep(1500);
  assert.equal(sendsOfType('crisis').length, 1, 'exactly one crisis push across two instances');
  assert.deepEqual(sendsOfType('crisis')[0].tokens, ['tokT']);
  assert.equal(sendsOfType('crisis')[0].channel, 'clinical_critical');
  const latest = (await getData(`users/${p.uid}`)).latestVitals;
  assert.equal(latest.heartRate.value, 150);

  // PHQ-9 item 9 -> critical crisis + push; chat message -> push; appointment -> meeting url + push.
  await db.doc('clinical_assessments/as1').set({
    patientId: p.uid, therapistId: t.uid, type: 'phq9_gad7', totalScore: 9, item9: 1,
    phq9Answers: [1, 1, 1, 1, 1, 1, 1, 1, 1], timestamp: FieldValue.serverTimestamp(),
  });
  const chatId = [p.uid, t.uid].sort().join('__');
  await db.doc(`chats/${chatId}/messages/m1`).set({
    id: 'm1', senderId: p.uid, receiverId: t.uid, senderName: 'Pat Smoke', text: 'hello',
    createdAt: FieldValue.serverTimestamp(), read: false,
  });
  await db.doc('appointments/ap1').set({
    patientId: p.uid, therapistId: t.uid, patientName: 'Pat Smoke', therapistName: 'Dr Smoke',
    requestedBy: 'therapist', status: 'scheduled', scheduledAt: Timestamp.fromMillis(Date.now() + 86400000),
    durationMinutes: 30, isVirtual: true, meetingUrl: null,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  const asCrisis = await waitFor(() => getData('crisis_events/assessment_as1'), 'assessment crisis');
  assert.equal(asCrisis.severity, 'critical');
  await waitFor(async () => (await getData('appointments/ap1')).meetingUrl, 'meeting url');
  await waitFor(() => sendsOfType('chat').length >= 1 && sendsOfType('appointment').length >= 1 &&
    sendsOfType('crisis').length >= 2, 'chat/appointment/assessment pushes');
  await sleep(2000);
  assert.equal(sendsOfType('chat').length, 1, 'one chat push');
  assert.equal(sendsOfType('appointment').length, 1, 'one appointment push (own meetingUrl write does not re-notify)');
  assert.equal(sendsOfType('crisis').length, 2, 'vital + assessment crisis pushes');
  // Appointment update: therapist cancels -> patient notified once.
  await db.doc('appointments/ap1').update({ status: 'cancelled', cancelledBy: t.uid, updatedAt: FieldValue.serverTimestamp() });
  await waitFor(() => sendsOfType('appointment').length >= 2, 'cancel push');
  await sleep(1500);
  assert.equal(sendsOfType('appointment').length, 2);
  // C-SSRS high: the patient app writes its immediate alert under the same
  // deterministic id first; the runner must merge (critical) and push once.
  await db.doc('crisis_events/assessment_cs1').set({
    patientId: p.uid, therapistId: t.uid, patientName: 'Pat Smoke', eventType: 'cssrs_high',
    severity: 'critical', title: 'C-SSRS high risk', message: 'client alert', acknowledged: false,
    timestamp: FieldValue.serverTimestamp(), source: 'assessment',
  });
  await db.doc('clinical_assessments/cs1').set({
    patientId: p.uid, therapistId: t.uid, type: 'cssrs', cssrsRisk: 'high',
    cssrsAnswers: { q1: true, q2: true, q3: true, q4: true, q5: true, q6: true, q6Recent: true },
    timestamp: FieldValue.serverTimestamp(),
  });
  const cs = await waitFor(async () => {
    const d = await getData('crisis_events/assessment_cs1');
    return d && d.serverVerified ? d : null;
  }, 'cssrs crisis merged by runner');
  assert.equal(cs.severity, 'critical');
  assert.equal(cs.eventType, 'cssrs_high');
  await waitFor(() => sendsOfType('crisis').length >= 3, 'cssrs push');
  await sleep(1500);
  assert.equal(sends.filter((x) => x.data.eventId === 'assessment_cs1').length, 1, 'one cssrs push');
  assert.equal(sendsOfType('crisis').length, 3);
  console.log('runner (two concurrent instances): OK');

  // ------------------------------------------------ restart: no duplicates
  await Promise.all([a.stop(), b.stop()]);
  const before = sends.length;
  const receiptsBefore = (await db.collection('push_receipts').get()).size;
  a = newRunner('smokeA'); // same instance: resumes from its watermark
  const c = newRunner('smokeC'); // brand-new instance: 15-min lookback replays history
  await Promise.all([a.start(), c.start()]);
  await sleep(4000);
  assert.equal(sends.length, before, 'restart must not re-send any push');
  assert.equal((await db.collection('push_receipts').get()).size, receiptsBefore);
  const crises = await db.collection('crisis_events').where('patientId', '==', p.uid).get();
  assert.equal(crises.size, 3, 'no duplicate crisis events');
  const st = a.status().listeners.find((l) => l.name === 'vitals');
  assert.equal(st.processed, 0, 'resumed instance did not reprocess the vital');

  // A change made while "down" is picked up after restart.
  await a.stop();
  await c.stop();
  const vital2 = `${p.uid}_heart_rate_${Date.now()}`;
  await db.doc(`vitals/${vital2}`).set({
    patientId: p.uid, therapistId: t.uid, type: 'heart_rate', value: 30, unit: 'bpm',
    measuredAt: Timestamp.now(), source: 'wear_os', createdAt: FieldValue.serverTimestamp(),
  });
  a = newRunner('smokeA');
  await a.start();
  const low = await waitFor(() => getData(`crisis_events/vital_${vital2}`), 'crisis for vital written while down');
  assert.equal(low.eventType, 'vital_low');
  await waitFor(() => sendsOfType('crisis').length === 4, 'push for vital written while down');
  await a.stop();
  console.log('runner restart (no duplicates, catch-up): OK');

  // ------------------------------- push_receipts claim under contention
  const { createBackendCore } = require('../../src/firebase/coreLoader');
  const cores = [0, 1].map(() => createBackendCore(admin, { messaging: () => fakeMessaging, logger: quiet }));
  const n0 = sends.length;
  const results = await Promise.allSettled(Array.from({ length: 6 }, (_, i) => cores[i % 2].push.sendPushToUser({
    uid: t.uid, app: 'therapist', channelId: 'clinical_critical', title: 'x', body: 'y',
    data: { type: 'race' }, receiptKey: 'race_test_1',
  })));
  assert.equal(sends.length - n0, 1, 'exactly one FCM send under contention');
  for (const res of results) {
    if (res.status === 'rejected') assert.match(res.reason.message, /being processed|contention|ABORTED|aborted/i);
  }
  console.log('push_receipts transactional claim: OK');

  // ------------------------------------------ orphan sweep (Auth deletions)
  const gone = await auth.createUser({ email: 'gone@x.test', password: 'secret123' });
  await db.doc(`users/${gone.uid}`).set({ role: 'patient', name: 'Gone' });
  await db.doc('fcm_tokens/tokGone').set({ uid: gone.uid, platform: 'android', app: 'patient', updatedAt: Timestamp.now() });
  await auth.deleteUser(gone.uid);
  const { sweepOrphanedAccounts } = require('../../src/firebase/orphanSweep');
  const sweep = await sweepOrphanedAccounts({
    db: () => db, auth: () => auth, cleanupDeletedUser: cores[0].triggers.cleanupDeletedUser, logger: quiet,
  });
  assert.deepEqual(sweep.cleaned, [gone.uid]);
  assert.equal(await getData(`users/${gone.uid}`), null);
  assert.equal(await getData('fcm_tokens/tokGone'), null);
  assert.ok(await getData(`users/${p.uid}`), 'live users kept');
  console.log('orphan sweep: OK');

  await fr.stop();
  server.close();
  console.log('SMOKE OK');
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
