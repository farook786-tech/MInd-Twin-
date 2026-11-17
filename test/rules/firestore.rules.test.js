'use strict';

/**
 * Firestore security rules tests. Run against the emulator:
 *   cd test/rules && npm install && npm run test:emulator
 */

const fs = require('node:fs');
const path = require('node:path');
const { describe, it, before, after, beforeEach } = require('node:test');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection, query, where, orderBy,
  getDocs, serverTimestamp, Timestamp, writeBatch, increment,
} = require('firebase/firestore');

let env;
const RULES = fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');

const PAST = Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);
const FUTURE = Timestamp.fromMillis(Date.now() + 2 * 24 * 60 * 60 * 1000);

const patient = () => env.authenticatedContext('p1', { role: 'patient' }).firestore();
const otherPatient = () => env.authenticatedContext('p2', { role: 'patient' }).firestore();
const therapist = () => env.authenticatedContext('t1', { role: 'therapist' }).firestore();
const otherTherapist = () => env.authenticatedContext('t2', { role: 'therapist' }).firestore();
const pendingTherapist = () => env.authenticatedContext('tp', { role: 'therapist_pending' }).firestore();
const noRole = () => env.authenticatedContext('p3', {}).firestore();
const anon = () => env.unauthenticatedContext().firestore();

async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const w = (p, d) => setDoc(doc(db, p), d);
    await w('users/t1', { role: 'therapist', status: 'approved', name: 'Dr One', inviteCode: 'ABCDEFGH' });
    await w('users/t2', { role: 'therapist', status: 'approved', name: 'Dr Two' });
    await w('users/tp', { role: 'therapist_pending', status: 'pending', name: 'Dr Pending' });
    await w('users/p1', { role: 'patient', therapistId: 't1', therapistName: 'Dr One', name: 'Pat' });
    await w('users/p2', { role: 'patient', therapistId: 't2', therapistName: 'Dr Two', name: 'Other' });
    await w('invite_codes/ABCDEFGH', { therapistId: 't1', active: true });
    await w('daily_logs/l1', { patientId: 'p1', therapistId: 't1', timestamp: PAST, riskScore: 50 });
    await w('daily_logs/l2', { patientId: 'p2', therapistId: 't2', timestamp: PAST, riskScore: 10 });
    await w('clinical_assessments/a1', { patientId: 'p1', therapistId: 't1', timestamp: PAST, phq9Score: 5 });
    await w('vitals/v1', {
      patientId: 'p1', therapistId: 't1', type: 'heart_rate', value: 80, unit: 'bpm',
      measuredAt: PAST, source: 'wear_os', createdAt: PAST,
    });
    await w('crisis_events/c1', {
      patientId: 'p1', therapistId: 't1', patientName: 'Pat', eventType: 'vital_high',
      severity: 'high', title: 't', message: 'm', acknowledged: false, timestamp: PAST,
    });
    await w('crisis_events/c2', {
      patientId: 'p2', therapistId: 't2', eventType: 'sos', severity: 'critical',
      acknowledged: false, timestamp: PAST,
    });
    await w('fcm_tokens/tokP1', { uid: 'p1', platform: 'android', app: 'patient', updatedAt: PAST });
    await w('chats/p1__t1', {
      participants: ['p1', 't1'], names: { p1: 'Pat', t1: 'Dr One' }, lastMessage: 'hi',
      lastSenderId: 't1', lastMessageAt: PAST, unread: { p1: 2, t1: 0 },
    });
    await w('chats/p1__t1/messages/m1', {
      id: 'm1', senderId: 't1', receiverId: 'p1', senderName: 'Dr One', text: 'hi', createdAt: PAST, read: false,
    });
    await w('appointments/ap1', {
      patientId: 'p1', therapistId: 't1', patientName: 'Pat', therapistName: 'Dr One',
      requestedBy: 'patient', status: 'requested', scheduledAt: null, proposedAt: FUTURE,
      durationMinutes: 30, isVirtual: true, meetingUrl: null, reason: 'r', notes: '',
      createdAt: PAST, updatedAt: PAST,
    });
    await w('appointments/ap2', {
      patientId: 'p1', therapistId: 't1', requestedBy: 'therapist', status: 'scheduled',
      scheduledAt: FUTURE, proposedAt: null, durationMinutes: 60, isVirtual: true,
      meetingUrl: 'https://meet.jit.si/MindTwin-ap2-abcdefghij', createdAt: PAST, updatedAt: PAST,
    });
    await w('appointments/ap1/notes/n1', { therapistId: 't1', text: 'note', createdAt: PAST });
    await w('anomalies/x1', { therapistId: 't1', dismissed: false });
  });
}

before(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-mindtwin',
    firestore: { rules: RULES, host, port: Number(port) },
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await seed();
});

// --------------------------------------------------------------------- users
describe('users', () => {
  it('owner reads own doc; unauthenticated cannot', async () => {
    await assertSucceeds(getDoc(doc(patient(), 'users/p1')));
    await assertFails(getDoc(doc(anon(), 'users/p1')));
  });
  it('assigned therapist reads patient; other therapist cannot', async () => {
    await assertSucceeds(getDoc(doc(therapist(), 'users/p1')));
    await assertFails(getDoc(doc(otherTherapist(), 'users/p1')));
  });
  it('pending therapist cannot read patients even if stamped', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'users/p1'), { therapistId: 'tp' }));
    await assertFails(getDoc(doc(pendingTherapist(), 'users/p1')));
  });
  it('patient cannot read another patient or their therapist doc', async () => {
    await assertFails(getDoc(doc(patient(), 'users/p2')));
    await assertFails(getDoc(doc(patient(), 'users/t1')));
  });
  it('therapist list must filter by therapistId', async () => {
    await assertSucceeds(getDocs(query(collection(therapist(), 'users'),
      where('role', '==', 'patient'), where('therapistId', '==', 't1'))));
    await assertFails(getDocs(query(collection(therapist(), 'users'), where('role', '==', 'patient'))));
    await assertFails(getDocs(query(collection(patient(), 'users'), where('role', '==', 'therapist'))));
    await assertFails(getDocs(query(collection(patient(), 'users'), where('email', '==', 'a@b.c'))));
  });
  it('owner may update client fields', async () => {
    await assertSucceeds(updateDoc(doc(patient(), 'users/p1'), {
      name: 'Pat 2', latestRiskScore: 40, lastCheckInAt: serverTimestamp(),
      latestVitals: { heartRate: { value: 70, measuredAt: PAST } },
    }));
  });
  it('owner cannot change server-owned fields', async () => {
    for (const f of [{ role: 'therapist' }, { therapistId: 't2' }, { therapistName: 'x' },
      { status: 'approved' }, { inviteCode: 'ZZZZZZZZ' }, { createdAt: serverTimestamp() },
      { vitalThresholds: { heartRateHigh: 200 } }]) {
      await assertFails(updateDoc(doc(patient(), 'users/p1'), f));
    }
  });
  it('owner validation: risk score range', async () => {
    await assertFails(updateDoc(doc(patient(), 'users/p1'), { latestRiskScore: 101 }));
  });
  it('new user may create bare profile without server fields', async () => {
    await assertSucceeds(setDoc(doc(noRole(), 'users/p3'), { name: 'New' }));
    await assertFails(setDoc(doc(noRole(), 'users/p3'), { name: 'New', role: 'therapist' }));
    await assertFails(setDoc(doc(noRole(), 'users/p4'), { name: 'Not me' }));
  });
  it('owner may write PHQ/GAD snapshots, streak, latestMood (validated)', async () => {
    await assertSucceeds(updateDoc(doc(patient(), 'users/p1'), {
      latestPhq9: { total: 12, severity: 'moderate', at: serverTimestamp() },
      latestGad7: { total: 5, severity: 'mild', at: serverTimestamp() },
      streak: 3, latestMood: 'Okay',
    }));
    await assertFails(updateDoc(doc(patient(), 'users/p1'), { latestPhq9: { total: 28 } }));
    await assertFails(updateDoc(doc(patient(), 'users/p1'), { latestGad7: { total: 3, extra: 1 } }));
    await assertFails(updateDoc(doc(patient(), 'users/p1'), { streak: 1.5 }));
    await assertFails(updateDoc(doc(patient(), 'users/p1'), { streak: -1 }));
    await assertFails(updateDoc(doc(patient(), 'users/p1'), { latestMood: 'x'.repeat(65) }));
    await assertFails(updateDoc(doc(therapist(), 'users/p1'), { streak: 9 }));
  });
  it('vitalThresholds bounds: high 80-220, low 25-80, sleep 0-12, high > low', async () => {
    const t = (v) => updateDoc(doc(therapist(), 'users/p1'), { vitalThresholds: v });
    await assertSucceeds(t({ heartRateHigh: 220, heartRateLow: 25, sleepHoursLow: 12 }));
    await assertSucceeds(t({ heartRateHigh: 80, heartRateLow: 79, sleepHoursLow: 0 }));
    await assertSucceeds(t({ heartRateLow: 80 }));
    await assertFails(t({ heartRateHigh: 221 }));
    await assertFails(t({ heartRateHigh: 79 }));
    await assertFails(t({ heartRateLow: 24 }));
    await assertFails(t({ heartRateLow: 81 }));
    await assertFails(t({ sleepHoursLow: 12.5 }));
    await assertFails(t({ heartRateHigh: 80, heartRateLow: 80 }));
    await assertFails(t({ heartRateHigh: '100' }));
    await assertFails(t({ spo2Low: 90 }));
  });
  it('therapist may set ONLY valid vitalThresholds of own patient', async () => {
    await assertSucceeds(updateDoc(doc(therapist(), 'users/p1'),
      { vitalThresholds: { heartRateHigh: 110, heartRateLow: 50, sleepHoursLow: 5 } }));
    await assertFails(updateDoc(doc(therapist(), 'users/p1'), { vitalThresholds: { heartRateHigh: 1000 } }));
    await assertFails(updateDoc(doc(therapist(), 'users/p1'), { vitalThresholds: { heartRateHigh: 60, heartRateLow: 90 } }));
    await assertFails(updateDoc(doc(therapist(), 'users/p1'), { name: 'renamed' }));
    await assertFails(updateDoc(doc(otherTherapist(), 'users/p1'), { vitalThresholds: { heartRateHigh: 110 } }));
  });
  it('nobody deletes users', async () => {
    await assertFails(deleteDoc(doc(patient(), 'users/p1')));
  });
});

// -------------------------------------------------------------- invite_codes
describe('invite_codes', () => {
  it('no client access', async () => {
    await assertFails(getDoc(doc(therapist(), 'invite_codes/ABCDEFGH')));
    await assertFails(getDoc(doc(patient(), 'invite_codes/ABCDEFGH')));
    await assertFails(setDoc(doc(therapist(), 'invite_codes/ZZZZZZZZ'), { therapistId: 't1', active: true }));
  });
});

// ---------------------------------------------------------------- fcm_tokens
describe('fcm_tokens', () => {
  const tok = (uid) => ({ uid, platform: 'android', app: 'patient', updatedAt: serverTimestamp() });
  it('owner creates/reads/deletes own token', async () => {
    await assertSucceeds(setDoc(doc(patient(), 'fcm_tokens/newTok'), tok('p1')));
    await assertSucceeds(getDoc(doc(patient(), 'fcm_tokens/tokP1')));
    await assertSucceeds(getDocs(query(collection(patient(), 'fcm_tokens'), where('uid', '==', 'p1'))));
    await assertSucceeds(deleteDoc(doc(patient(), 'fcm_tokens/tokP1')));
  });
  it('cannot register a token for someone else or read others', async () => {
    await assertFails(setDoc(doc(patient(), 'fcm_tokens/evil'), tok('t1')));
    await assertFails(getDoc(doc(therapist(), 'fcm_tokens/tokP1')));
    await assertFails(deleteDoc(doc(therapist(), 'fcm_tokens/tokP1')));
    await assertFails(getDocs(collection(therapist(), 'fcm_tokens')));
  });
  it('rejects bad shape', async () => {
    await assertFails(setDoc(doc(patient(), 'fcm_tokens/x'), { ...tok('p1'), platform: 'web' }));
    await assertFails(setDoc(doc(patient(), 'fcm_tokens/x'), { ...tok('p1'), extra: 1 }));
  });
});

// -------------------------------------------------------------------- vitals
describe('vitals', () => {
  const vital = (over = {}) => ({
    patientId: 'p1', therapistId: 't1', type: 'heart_rate', value: 72, unit: 'bpm',
    measuredAt: Timestamp.now(), source: 'wear_os', createdAt: serverTimestamp(), ...over,
  });
  it('patient creates own vital with correct stamp', async () => {
    const ms = Date.now();
    await assertSucceeds(setDoc(doc(patient(), `vitals/p1_heart_rate_${ms}`),
      vital({ measuredAt: Timestamp.fromMillis(ms) })));
  });
  it('rejects wrong owner, wrong therapist stamp, bad unit, future time, extra fields', async () => {
    await assertFails(setDoc(doc(patient(), 'vitals/x1'), vital({ patientId: 'p2' })));
    await assertFails(setDoc(doc(patient(), 'vitals/x2'), vital({ therapistId: 't2' })));
    await assertFails(setDoc(doc(patient(), 'vitals/x3'), vital({ therapistId: '' })));
    await assertFails(setDoc(doc(patient(), 'vitals/x4'), vital({ unit: 'hours' })));
    await assertFails(setDoc(doc(patient(), 'vitals/x5'), vital({ measuredAt: FUTURE })));
    await assertFails(setDoc(doc(patient(), 'vitals/x6'), vital({ hacked: true })));
    await assertFails(setDoc(doc(patient(), 'vitals/x7'), vital({ value: '72' })));
    await assertFails(setDoc(doc(therapist(), 'vitals/x8'), vital()));
  });
  it('unlinked patient may upload with therapistId null', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/p3'), { name: 'N' }));
    const ctx = env.authenticatedContext('p3', {}).firestore();
    await assertSucceeds(setDoc(doc(ctx, 'vitals/p3_sleep_1'),
      vital({ patientId: 'p3', therapistId: null, type: 'sleep', unit: 'hours', value: 6 })));
    await assertFails(setDoc(doc(ctx, 'vitals/p3_sleep_2'),
      vital({ patientId: 'p3', therapistId: 't1', type: 'sleep', unit: 'hours', value: 6 })));
  });
  it('vitals are immutable', async () => {
    await assertFails(updateDoc(doc(patient(), 'vitals/v1'), { value: 60 }));
    await assertFails(deleteDoc(doc(patient(), 'vitals/v1')));
  });
  it('reads: owner + own therapist only; queries', async () => {
    await assertSucceeds(getDoc(doc(patient(), 'vitals/v1')));
    await assertSucceeds(getDoc(doc(therapist(), 'vitals/v1')));
    await assertFails(getDoc(doc(otherTherapist(), 'vitals/v1')));
    await assertFails(getDoc(doc(otherPatient(), 'vitals/v1')));
    await assertSucceeds(getDocs(query(collection(patient(), 'vitals'),
      where('patientId', '==', 'p1'), orderBy('measuredAt', 'desc'))));
    await assertSucceeds(getDocs(query(collection(therapist(), 'vitals'),
      where('patientId', '==', 'p1'), orderBy('measuredAt', 'desc'))));
    await assertFails(getDocs(query(collection(otherTherapist(), 'vitals'), where('patientId', '==', 'p1'))));
  });
});

// ------------------------------------------------- daily_logs / assessments
describe('daily_logs and clinical_assessments', () => {
  const log = (over = {}) => ({ patientId: 'p1', therapistId: 't1', timestamp: serverTimestamp(), riskScore: 20, ...over });
  it('patient creates own log stamped with real therapistId', async () => {
    await assertSucceeds(addDoc(collection(patient(), 'daily_logs'), log()));
    await assertSucceeds(addDoc(collection(patient(), 'clinical_assessments'), { patientId: 'p1', therapistId: 't1', timestamp: serverTimestamp(), phq9Score: 3 }));
  });
  it('rejects empty/foreign therapistId, foreign patient, missing timestamp, non-patient', async () => {
    await assertFails(addDoc(collection(patient(), 'daily_logs'), log({ therapistId: '' })));
    await assertFails(addDoc(collection(patient(), 'daily_logs'), log({ therapistId: 'Dr One' })));
    await assertFails(addDoc(collection(patient(), 'daily_logs'), log({ patientId: 'p2' })));
    await assertFails(addDoc(collection(patient(), 'daily_logs'), log({ timestamp: 'today' })));
    await assertFails(addDoc(collection(therapist(), 'daily_logs'), log()));
    await assertFails(addDoc(collection(noRole(), 'daily_logs'), log({ patientId: 'p3' })));
  });
  it('owner may merge ML results but not re-own or re-date; assessments immutable', async () => {
    await assertSucceeds(updateDoc(doc(patient(), 'daily_logs/l1'), { mlRisk: { riskScore: 30 } }));
    await assertFails(updateDoc(doc(patient(), 'daily_logs/l1'), { therapistId: 't2' }));
    await assertFails(updateDoc(doc(patient(), 'daily_logs/l1'), { timestamp: serverTimestamp() }));
    await assertFails(updateDoc(doc(therapist(), 'daily_logs/l1'), { riskScore: 0 }));
    await assertFails(updateDoc(doc(patient(), 'clinical_assessments/a1'), { phq9Score: 0 }));
    await assertFails(deleteDoc(doc(patient(), 'daily_logs/l1')));
  });
  it('queries used by the apps', async () => {
    await assertSucceeds(getDocs(query(collection(patient(), 'daily_logs'), where('patientId', '==', 'p1'))));
    await assertSucceeds(getDocs(query(collection(patient(), 'daily_logs'),
      where('patientId', '==', 'p1'), orderBy('timestamp', 'desc'))));
    await assertSucceeds(getDocs(query(collection(therapist(), 'daily_logs'), where('therapistId', '==', 't1'))));
    await assertSucceeds(getDocs(query(collection(therapist(), 'daily_logs'), where('patientId', '==', 'p1'))));
    await assertSucceeds(getDocs(query(collection(therapist(), 'clinical_assessments'), where('patientId', '==', 'p1'))));
    await assertFails(getDocs(query(collection(therapist(), 'daily_logs'), where('patientId', '==', 'p2'))));
    await assertFails(getDocs(collection(therapist(), 'daily_logs')));
    await assertFails(getDocs(query(collection(patient(), 'daily_logs'), where('patientId', '==', 'p2'))));
  });
});

// ------------------------------------------------------------- crisis_events
describe('crisis_events', () => {
  const sos = (over = {}) => ({
    patientId: 'p1', therapistId: 't1', patientName: 'Pat', eventType: 'sos', severity: 'critical',
    title: 'SOS', message: 'help', acknowledged: false, timestamp: serverTimestamp(), ...over,
  });
  it('patient creates sos/checkin_crisis/chat_crisis for self', async () => {
    for (const eventType of ['sos', 'checkin_crisis', 'chat_crisis']) {
      await assertSucceeds(addDoc(collection(patient(), 'crisis_events'), sos({ eventType })));
    }
    // PatientCrisisReporter extras
    await assertSucceeds(addDoc(collection(patient(), 'crisis_events'), sos({
      eventType: 'chat_crisis', clientCreatedAt: Timestamp.now(), source: 'ai_chat', details: { layer: 'lexicon' },
    })));
    await assertFails(addDoc(collection(patient(), 'crisis_events'), sos({ triggerLayer: 'x' })));
  });
  it('patient cannot forge server event types, other patients, or pre-acknowledge', async () => {
    await assertFails(addDoc(collection(patient(), 'crisis_events'), sos({ eventType: 'vital_high' })));
    await assertFails(addDoc(collection(patient(), 'crisis_events'), sos({ eventType: 'self_reported_help_needed' })));
    await assertFails(addDoc(collection(patient(), 'crisis_events'), sos({ patientId: 'p2', therapistId: 't2' })));
    await assertFails(addDoc(collection(patient(), 'crisis_events'), sos({ acknowledged: true })));
    await assertFails(addDoc(collection(patient(), 'crisis_events'), sos({ severity: 'low' })));
    await assertFails(addDoc(collection(therapist(), 'crisis_events'), sos()));
  });
  it('therapist acknowledges only', async () => {
    await assertSucceeds(updateDoc(doc(therapist(), 'crisis_events/c1'),
      { acknowledged: true, acknowledgedAt: serverTimestamp(), acknowledgedBy: 't1' }));
  });
  it('therapist cannot edit other fields / ack as someone else / ack other patients', async () => {
    await assertFails(updateDoc(doc(therapist(), 'crisis_events/c1'),
      { acknowledged: true, acknowledgedAt: serverTimestamp(), acknowledgedBy: 't1', severity: 'medium' }));
    await assertFails(updateDoc(doc(therapist(), 'crisis_events/c1'),
      { acknowledged: true, acknowledgedAt: serverTimestamp(), acknowledgedBy: 't2' }));
    await assertFails(updateDoc(doc(otherTherapist(), 'crisis_events/c1'),
      { acknowledged: true, acknowledgedAt: serverTimestamp(), acknowledgedBy: 't2' }));
    await assertFails(updateDoc(doc(patient(), 'crisis_events/c1'),
      { acknowledged: true, acknowledgedAt: serverTimestamp(), acknowledgedBy: 'p1' }));
    await assertFails(deleteDoc(doc(therapist(), 'crisis_events/c1')));
  });
  it('alert feed queries', async () => {
    await assertSucceeds(getDocs(query(collection(therapist(), 'crisis_events'),
      where('therapistId', '==', 't1'), where('acknowledged', '==', false))));
    await assertSucceeds(getDocs(query(collection(therapist(), 'crisis_events'),
      where('therapistId', '==', 't1'), orderBy('timestamp', 'desc'))));
    await assertSucceeds(getDocs(query(collection(patient(), 'crisis_events'),
      where('patientId', '==', 'p1'), orderBy('timestamp', 'desc'))));
    await assertFails(getDocs(query(collection(therapist(), 'crisis_events'), where('acknowledged', '==', false))));
    await assertFails(getDoc(doc(therapist(), 'crisis_events/c2')));
  });
});

// --------------------------------------------------------------------- chats
describe('chats', () => {
  const msg = (from, to, over = {}) => ({
    id: 'mx', senderId: from, receiverId: to, senderName: 'n', text: 'hello',
    createdAt: serverTimestamp(), read: false, ...over,
  });
  it('patient <-> own therapist: batch message + chat summary', async () => {
    const db = patient();
    const b = writeBatch(db);
    b.set(doc(db, 'chats/p1__t1/messages/mx'), msg('p1', 't1'));
    b.set(doc(db, 'chats/p1__t1'), {
      participants: ['p1', 't1'], names: { p1: 'Pat', t1: 'Dr One' }, lastMessage: 'hello',
      lastSenderId: 'p1', lastMessageAt: serverTimestamp(), unread: { t1: increment(1) },
    }, { merge: true });
    await assertSucceeds(b.commit());
  });
  it('first message creates chat doc', async () => {
    await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), 'chats/p1__t1')));
    const db = therapist();
    const b = writeBatch(db);
    b.set(doc(db, 'chats/p1__t1/messages/my'), msg('t1', 'p1', { id: 'my' }));
    b.set(doc(db, 'chats/p1__t1'), {
      participants: ['p1', 't1'], lastMessage: 'hello', lastSenderId: 't1',
      lastMessageAt: serverTimestamp(), unread: { p1: increment(1) },
    }, { merge: true });
    await assertSucceeds(b.commit());
  });
  it('patient cannot chat with a therapist that is not theirs', async () => {
    await assertFails(setDoc(doc(patient(), 'chats/p1__t2/messages/m'), msg('p1', 't2', { id: 'm' })));
    await assertFails(setDoc(doc(patient(), 'chats/p1__t2'), { participants: ['p1', 't2'] }));
    await assertFails(setDoc(doc(patient(), 'chats/p1__p2/messages/m'), msg('p1', 'p2', { id: 'm' })));
  });
  it('non-participants cannot read; participants can', async () => {
    await assertSucceeds(getDocs(query(collection(patient(), 'chats/p1__t1/messages'), orderBy('createdAt'))));
    await assertSucceeds(getDoc(doc(therapist(), 'chats/p1__t1')));
    await assertFails(getDoc(doc(otherTherapist(), 'chats/p1__t1')));
    await assertFails(getDocs(collection(otherPatient(), 'chats/p1__t1/messages')));
    await assertSucceeds(getDocs(query(collection(patient(), 'chats'),
      where('participants', 'array-contains', 'p1'), orderBy('lastMessageAt', 'desc'))));
    await assertFails(getDocs(query(collection(patient(), 'chats'), where('participants', 'array-contains', 't1'))));
  });
  it('cannot spoof sender, wrong receiver, non-canonical chat id', async () => {
    await assertFails(setDoc(doc(patient(), 'chats/p1__t1/messages/m'), msg('t1', 'p1', { id: 'm' })));
    await assertFails(setDoc(doc(patient(), 'chats/p1__t1/messages/m'), msg('p1', 'p2', { id: 'm' })));
    await assertFails(setDoc(doc(patient(), 'chats/t1__p1/messages/m'), msg('p1', 't1', { id: 'm' })));
    await assertFails(setDoc(doc(patient(), 'chats/p1__t1/messages/m'), msg('p1', 't1', { id: 'other' })));
    await assertFails(setDoc(doc(patient(), 'chats/p1__t1/messages/m'), msg('p1', 't1', { id: 'm', read: true })));
  });
  it('receiver marks read; sender cannot; no edits', async () => {
    await assertSucceeds(updateDoc(doc(patient(), 'chats/p1__t1/messages/m1'), { read: true }));
    await assertFails(updateDoc(doc(therapist(), 'chats/p1__t1/messages/m1'), { read: true }));
    await assertFails(updateDoc(doc(patient(), 'chats/p1__t1/messages/m1'), { text: 'edited' }));
    await assertFails(deleteDoc(doc(therapist(), 'chats/p1__t1/messages/m1')));
  });
  it('reader resets only own unread; cannot touch the other counter', async () => {
    await assertSucceeds(updateDoc(doc(patient(), 'chats/p1__t1'), { 'unread.p1': 0 }));
    await assertFails(updateDoc(doc(patient(), 'chats/p1__t1'), { 'unread.t1': 5 }));
    await assertFails(updateDoc(doc(patient(), 'chats/p1__t1'), { participants: ['p1', 'p2'] }));
    await assertFails(updateDoc(doc(patient(), 'chats/p1__t1'), { lastMessage: 'x', lastSenderId: 't1' }));
  });
});

// -------------------------------------------------------------- appointments
describe('appointments', () => {
  const req = (over = {}) => ({
    patientId: 'p1', therapistId: 't1', patientName: 'Pat', therapistName: 'Dr One',
    requestedBy: 'patient', status: 'requested', scheduledAt: null, proposedAt: FUTURE,
    durationMinutes: 45, isVirtual: true, meetingUrl: null, reason: 'talk', notes: '',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
  });
  const sched = (over = {}) => req({
    requestedBy: 'therapist', status: 'scheduled', scheduledAt: FUTURE, proposedAt: null, ...over,
  });
  it('patient requests with own therapist only', async () => {
    await assertSucceeds(addDoc(collection(patient(), 'appointments'), req()));
    await assertFails(addDoc(collection(patient(), 'appointments'), req({ therapistId: 't2' })));
    await assertFails(addDoc(collection(patient(), 'appointments'), req({ status: 'scheduled' })));
    await assertFails(addDoc(collection(patient(), 'appointments'), req({ meetingUrl: 'https://evil' })));
    await assertFails(addDoc(collection(patient(), 'appointments'), req({ scheduledAt: FUTURE })));
    await assertFails(addDoc(collection(patient(), 'appointments'), req({ durationMinutes: 90 })));
    await assertFails(addDoc(collection(patient(), 'appointments'), req({ patientId: 'p2', therapistId: 't2' })));
  });
  it('therapist schedules directly only for own patient', async () => {
    await assertSucceeds(addDoc(collection(therapist(), 'appointments'), sched()));
    await assertFails(addDoc(collection(otherTherapist(), 'appointments'), sched({ therapistId: 't2' })));
    await assertFails(addDoc(collection(therapist(), 'appointments'), sched({ status: 'requested' })));
    await assertFails(addDoc(collection(therapist(), 'appointments'), sched({ meetingUrl: 'https://x' })));
    await assertFails(addDoc(collection(pendingTherapist(), 'appointments'), sched({ therapistId: 'tp' })));
  });
  it('patient may only cancel', async () => {
    await assertSucceeds(updateDoc(doc(patient(), 'appointments/ap1'),
      { status: 'cancelled', cancelledBy: 'p1', updatedAt: serverTimestamp() }));
  });
  it('patient cannot schedule, edit notes or set meetingUrl', async () => {
    await assertFails(updateDoc(doc(patient(), 'appointments/ap1'),
      { status: 'scheduled', scheduledAt: FUTURE, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(patient(), 'appointments/ap1'), { notes: 'x', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(patient(), 'appointments/ap1'),
      { meetingUrl: 'https://x', updatedAt: serverTimestamp() }));
  });
  it('therapist lifecycle', async () => {
    await assertSucceeds(updateDoc(doc(therapist(), 'appointments/ap1'),
      { status: 'scheduled', scheduledAt: FUTURE, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(therapist(), 'appointments/ap2'),
      { status: 'completed', notes: 'done', updatedAt: serverTimestamp() }));
  });
  it('therapist decline / cancel', async () => {
    await assertSucceeds(updateDoc(doc(therapist(), 'appointments/ap1'),
      { status: 'declined', notes: 'Declined: busy', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(therapist(), 'appointments/ap2'),
      { status: 'cancelled', cancelledBy: 't1', updatedAt: serverTimestamp() }));
  });
  it('therapist cannot set meetingUrl, make invalid transitions, or touch others', async () => {
    await assertFails(updateDoc(doc(therapist(), 'appointments/ap2'),
      { meetingUrl: 'https://evil', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(therapist(), 'appointments/ap1'),
      { status: 'completed', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(therapist(), 'appointments/ap1'),
      { status: 'scheduled', updatedAt: serverTimestamp() }), 'scheduled needs scheduledAt');
    await assertFails(updateDoc(doc(therapist(), 'appointments/ap1'),
      { status: 'cancelled', cancelledBy: 'p1', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(otherTherapist(), 'appointments/ap1'),
      { status: 'declined', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(therapist(), 'appointments/ap1')));
  });
  it('queries', async () => {
    await assertSucceeds(getDocs(query(collection(patient(), 'appointments'),
      where('patientId', '==', 'p1'), where('scheduledAt', '>=', Timestamp.now()))));
    await assertSucceeds(getDocs(query(collection(patient(), 'appointments'),
      where('patientId', '==', 'p1'), where('status', '==', 'requested'))));
    await assertSucceeds(getDocs(query(collection(therapist(), 'appointments'),
      where('therapistId', '==', 't1'), where('patientId', '==', 'p1'))));
    await assertSucceeds(getDocs(query(collection(therapist(), 'appointments'),
      where('therapistId', '==', 't1'), where('status', '==', 'scheduled'))));
    await assertFails(getDocs(query(collection(otherTherapist(), 'appointments'), where('patientId', '==', 'p1'))));
    await assertFails(getDoc(doc(otherPatient(), 'appointments/ap1')));
  });
  it('session notes: therapist of appointment only, append-only', async () => {
    await assertSucceeds(addDoc(collection(therapist(), 'appointments/ap1/notes'),
      { therapistId: 't1', text: 'n', createdAt: serverTimestamp() }));
    await assertSucceeds(getDocs(query(collection(therapist(), 'appointments/ap1/notes'), orderBy('createdAt', 'desc'))));
    await assertFails(getDocs(collection(patient(), 'appointments/ap1/notes')));
    await assertFails(addDoc(collection(otherTherapist(), 'appointments/ap1/notes'),
      { therapistId: 't2', text: 'n', createdAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(therapist(), 'appointments/ap1/notes/n1'), { text: 'edit' }));
    await assertFails(deleteDoc(doc(therapist(), 'appointments/ap1/notes/n1')));
  });
});

// ----------------------------------------------------------------- default deny
// ------------------------------------------------- reconciliation (round 2)
async function makeUnlinked() {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/p3'), { name: 'New' }));
  return env.authenticatedContext('p3', {}).firestore();
}

describe('unlinked patient (therapistId null)', () => {
  it('may create logs, assessments, crisis, journal with therapistId null only', async () => {
    const db = await makeUnlinked();
    await assertSucceeds(addDoc(collection(db, 'daily_logs'),
      { patientId: 'p3', therapistId: null, timestamp: serverTimestamp(), riskScore: 10 }));
    await assertSucceeds(addDoc(collection(db, 'clinical_assessments'),
      { patientId: 'p3', therapistId: null, timestamp: serverTimestamp(), type: 'phq9_gad7', totalScore: 3 }));
    await assertSucceeds(addDoc(collection(db, 'crisis_events'), {
      patientId: 'p3', therapistId: null, eventType: 'sos', severity: 'critical',
      acknowledged: false, timestamp: serverTimestamp(),
    }));
    await assertSucceeds(addDoc(collection(db, 'journal_entries'), {
      patientId: 'p3', therapistId: null, source: 'voice_journal', text: 't', createdAt: serverTimestamp(),
    }));
    await assertFails(addDoc(collection(db, 'daily_logs'),
      { patientId: 'p3', therapistId: 't1', timestamp: serverTimestamp() }));
    await assertFails(addDoc(collection(db, 'daily_logs'),
      { patientId: 'p3', timestamp: serverTimestamp() }), 'therapistId key required');
  });
  it('linked patient may not write therapistId null; pending therapist may not write patient docs', async () => {
    await assertFails(addDoc(collection(patient(), 'daily_logs'),
      { patientId: 'p1', therapistId: null, timestamp: serverTimestamp() }));
    await assertFails(addDoc(collection(pendingTherapist(), 'daily_logs'),
      { patientId: 'tp', therapistId: null, timestamp: serverTimestamp() }));
  });
});

describe('daily_logs field whitelist', () => {
  const full = () => ({
    patientId: 'p1', therapistId: 't1', timestamp: serverTimestamp(), clientCreatedAt: Timestamp.now(),
    riskScore: 42.5, riskScoreSource: 'heuristic', wellbeingScore: 57.5, mood: 'Okay', moodKey: 'okay',
    moodScore: 3, sleep: 'Good', sleepKey: 'good', sleepScore: 4, energy: 'Low', energyKey: 'low',
    energyScore: 2, worries: ['work'], positives: ['friends'], dailyGoal: 'walk', dailyGoalKey: 'walk',
    goalLabel: 'walk', goalCompleted: false, summaryText: 's', optionalNote: 'n',
    breathingExerciseDone: true, breathingFeedback: 'better', thoughtDump: 'td', thoughtDumpSentiment: 'neutral',
  });
  it('accepts the full app payload', async () => {
    await assertSucceeds(addDoc(collection(patient(), 'daily_logs'), full()));
  });
  it('rejects unknown keys and out-of-range scores', async () => {
    await assertFails(addDoc(collection(patient(), 'daily_logs'), { ...full(), hacked: 1 }));
    await assertFails(addDoc(collection(patient(), 'daily_logs'), { ...full(), riskScore: 101 }));
    await assertFails(addDoc(collection(patient(), 'daily_logs'), { ...full(), riskScore: '50' }));
    await assertFails(addDoc(collection(patient(), 'daily_logs'), { ...full(), wellbeingScore: -1 }));
  });
  it('update: only mlSentiment/mlRisk/mlAnomaly maps', async () => {
    await assertSucceeds(updateDoc(doc(patient(), 'daily_logs/l1'),
      { mlSentiment: { score: 0.1 }, mlRisk: { riskScore: 80 }, mlAnomaly: { anomalyDetected: false } }));
    await assertFails(updateDoc(doc(patient(), 'daily_logs/l1'), { riskScore: 5 }));
    await assertFails(updateDoc(doc(patient(), 'daily_logs/l1'), { goalCompleted: true }));
    await assertFails(updateDoc(doc(patient(), 'daily_logs/l1'), { mlRisk: 'high' }));
    await assertFails(updateDoc(doc(otherPatient(), 'daily_logs/l1'), { mlRisk: { riskScore: 1 } }));
  });
  it('therapist scoped query (patientId + therapistId + orderBy timestamp)', async () => {
    await assertSucceeds(getDocs(query(collection(therapist(), 'daily_logs'),
      where('patientId', '==', 'p1'), where('therapistId', '==', 't1'), orderBy('timestamp', 'desc'))));
    await assertFails(getDocs(query(collection(otherTherapist(), 'daily_logs'),
      where('patientId', '==', 'p1'), where('therapistId', '==', 't1'))));
  });
});

describe('clinical_assessments field whitelist', () => {
  const current = () => ({
    patientId: 'p1', therapistId: 't1', type: 'phq9_gad7', totalScore: 10, item9: 1,
    phq9Answers: [1, 1, 1, 1, 1, 1, 1, 2, 1], phq9Severity: 'moderate', phq9Score: 10,
    gad7Score: 4, gad7Answers: [1, 1, 1, 1, 0, 0, 0], gad7Severity: 'minimal',
    answers: { phq9: [1, 1, 1, 1, 1, 1, 1, 2, 1], gad7: [1, 1, 1, 1, 0, 0, 0] },
    timestamp: serverTimestamp(), clientCreatedAt: Timestamp.now(),
  });
  it('accepts current and legacy payloads', async () => {
    await assertSucceeds(addDoc(collection(patient(), 'clinical_assessments'), current()));
    await assertSucceeds(setDoc(doc(patient(), 'clinical_assessments/p1_123'), {
      patientId: 'p1', therapistId: 't1', type: 'phq9_gad7', phq9Score: 4, gad7Score: 2,
      answers: { phq9: [0, 0, 0, 1, 1, 1, 1, 0, 0] }, timestamp: serverTimestamp(), legacyQueued: true,
    }));
  });
  it('rejects unknown keys and malformed scores', async () => {
    await assertFails(addDoc(collection(patient(), 'clinical_assessments'), { ...current(), riskScore: 5 }));
    await assertFails(addDoc(collection(patient(), 'clinical_assessments'), { ...current(), item9: 4 }));
    await assertFails(addDoc(collection(patient(), 'clinical_assessments'), { ...current(), totalScore: 28 }));
    await assertFails(addDoc(collection(patient(), 'clinical_assessments'), { ...current(), phq9Answers: [1, 1] }));
    await assertFails(addDoc(collection(patient(), 'clinical_assessments'), { ...current(), legacyQueued: 'yes' }));
  });
  it('therapist query with patientId + therapistId ordered by timestamp', async () => {
    await assertSucceeds(getDocs(query(collection(therapist(), 'clinical_assessments'),
      where('patientId', '==', 'p1'), where('therapistId', '==', 't1'), orderBy('timestamp'))));
  });
});

describe('crisis_events extras', () => {
  it('checkin and chat details maps accepted', async () => {
    const base = {
      patientId: 'p1', therapistId: 't1', patientName: 'Pat', severity: 'high', title: 'T', message: 'M',
      acknowledged: false, timestamp: serverTimestamp(), clientCreatedAt: Timestamp.now(),
    };
    await assertSucceeds(addDoc(collection(patient(), 'crisis_events'), {
      ...base, eventType: 'checkin_crisis', source: 'daily_checkin',
      details: { mood: 'sad', energy: 'drained', worries: ['a', 'b'] },
    }));
    await assertSucceeds(addDoc(collection(patient(), 'crisis_events'), {
      ...base, eventType: 'chat_crisis', source: 'ai_chat',
      details: { triggerLayer: 'lexicon', matchedPhrases: ['x'], confidence: 0.9, modelVersion: 'v1' },
    }));
    await assertFails(addDoc(collection(patient(), 'crisis_events'), { ...base, eventType: 'sos', details: 'str' }));
  });
});

describe('journal_entries', () => {
  const entry = (over = {}) => ({
    patientId: 'p1', therapistId: 't1', source: 'voice_journal', text: 'today was hard',
    transcript: null, durationSeconds: 42, hasAudio: true, audioUploaded: false,
    createdAt: serverTimestamp(), clientCreatedAt: Timestamp.now(), ...over,
  });
  it('patient creates, reads and deletes own entry', async () => {
    const ref = await assertSucceeds(addDoc(collection(patient(), 'journal_entries'), entry()));
    await assertSucceeds(getDoc(doc(patient(), `journal_entries/${ref.id}`)));
    await assertFails(updateDoc(doc(patient(), `journal_entries/${ref.id}`), { text: 'edited' }));
    await assertFails(deleteDoc(doc(therapist(), `journal_entries/${ref.id}`)));
    await assertSucceeds(deleteDoc(doc(patient(), `journal_entries/${ref.id}`)));
  });
  it('validation', async () => {
    await assertSucceeds(addDoc(collection(patient(), 'journal_entries'), entry({ text: 'x'.repeat(10000) })));
    await assertFails(addDoc(collection(patient(), 'journal_entries'), entry({ text: 'x'.repeat(10001) })));
    await assertFails(addDoc(collection(patient(), 'journal_entries'), entry({ source: 'other' })));
    await assertFails(addDoc(collection(patient(), 'journal_entries'), entry({ extra: 1 })));
    await assertFails(addDoc(collection(patient(), 'journal_entries'), entry({ therapistId: 't2' })));
    await assertFails(addDoc(collection(patient(), 'journal_entries'), entry({ createdAt: Timestamp.now() })));
    await assertFails(addDoc(collection(therapist(), 'journal_entries'), entry({ patientId: 't1' })));
  });
  it('linked therapist reads via scoped query; others cannot', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'journal_entries/j1'),
      { patientId: 'p1', therapistId: 't1', source: 'voice_journal', text: 't', createdAt: PAST }));
    await assertSucceeds(getDocs(query(collection(therapist(), 'journal_entries'),
      where('patientId', '==', 'p1'), where('therapistId', '==', 't1'), orderBy('createdAt', 'desc'))));
    await assertSucceeds(getDoc(doc(therapist(), 'journal_entries/j1')));
    await assertFails(getDoc(doc(otherTherapist(), 'journal_entries/j1')));
    await assertFails(getDoc(doc(otherPatient(), 'journal_entries/j1')));
    await assertFails(getDocs(query(collection(otherTherapist(), 'journal_entries'),
      where('patientId', '==', 'p1'))));
  });
});

describe('reminders', () => {
  const rem = (over = {}) => ({
    patientId: 'p1', type: 'walk', scheduledAt: FUTURE, completed: false, createdAt: serverTimestamp(), ...over,
  });
  it('patient creates, reads, completes own reminder', async () => {
    const ref = doc(collection(patient(), 'reminders'));
    await assertSucceeds(setDoc(ref, rem()));
    const id = ref.id;
    await assertSucceeds(getDocs(query(collection(patient(), 'reminders'), where('patientId', '==', 'p1'))));
    await assertSucceeds(updateDoc(doc(patient(), `reminders/${id}`), { completed: true }));
    await assertFails(updateDoc(doc(patient(), `reminders/${id}`), { type: 'run' }));
    await assertFails(getDoc(doc(therapist(), `reminders/${id}`)));
    await assertFails(getDoc(doc(otherPatient(), `reminders/${id}`)));
    await assertFails(updateDoc(doc(otherPatient(), `reminders/${id}`), { completed: true }));
    await assertFails(deleteDoc(doc(patient(), `reminders/${id}`)));
  });
  it('validation', async () => {
    await assertFails(addDoc(collection(patient(), 'reminders'), rem({ patientId: 'p2' })));
    await assertFails(addDoc(collection(patient(), 'reminders'), rem({ completed: true })));
    await assertFails(addDoc(collection(patient(), 'reminders'), rem({ scheduledAt: 'tomorrow' })));
    await assertFails(addDoc(collection(patient(), 'reminders'), rem({ extra: 1 })));
    await assertFails(addDoc(collection(therapist(), 'reminders'), rem({ patientId: 't1' })));
  });
});

describe('immediate PHQ-9 crisis (assessment_<id>) and daily-log ML fields', () => {
  const phq = (over = {}) => ({
    patientId: 'p1', therapistId: 't1', patientName: 'Pat', eventType: 'phq9_severe', severity: 'critical',
    title: 'PHQ-9 alert', message: 'item 9', acknowledged: false, timestamp: serverTimestamp(),
    clientCreatedAt: Timestamp.now(), source: 'phq9_assessment',
    details: { assessmentId: 'A1', item9: 2, totalScore: 14, modelUsed: 'rules', triggerLayer: 'item9', matchedPhrases: [] },
    ...over,
  });
  it('patient may create phq9_severe only under assessment_<id>', async () => {
    await assertSucceeds(setDoc(doc(patient(), 'crisis_events/assessment_A1'), phq()));
    await assertSucceeds(setDoc(doc(patient(), 'crisis_events/assessment_A2'), phq({ severity: 'high' })));
    await assertFails(setDoc(doc(patient(), 'crisis_events/assessment_A3'), phq({ severity: 'medium' })));
    await assertFails(setDoc(doc(patient(), 'crisis_events/random123'), phq()));
    await assertFails(addDoc(collection(patient(), 'crisis_events'), phq()));
    await assertFails(setDoc(doc(patient(), 'crisis_events/assessment_A4'), phq({ eventType: 'high_risk' })));
    await assertFails(setDoc(doc(otherPatient(), 'crisis_events/assessment_A5'),
      phq({ patientId: 'p1' })));
  });
  it('patient write to an assessment_<id> the function already created is denied', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'crisis_events/assessment_B1'), {
      patientId: 'p1', therapistId: 't1', eventType: 'phq9_severe', severity: 'critical',
      acknowledged: false, timestamp: PAST, source: 'assessment',
    }));
    await assertFails(setDoc(doc(patient(), 'crisis_events/assessment_B1'), phq()));
  });
  it('sos from chat with details', async () => {
    await assertSucceeds(addDoc(collection(patient(), 'crisis_events'), phq({
      eventType: 'sos', source: 'ai_chat', details: { triggerLayer: 'button' },
    })));
  });
  it('daily log with null scores and mlSentiment.crisisText at create', async () => {
    await assertSucceeds(addDoc(collection(patient(), 'daily_logs'), {
      patientId: 'p1', therapistId: 't1', timestamp: serverTimestamp(), clientCreatedAt: Timestamp.now(),
      riskScore: null, wellbeingScore: null, riskScoreSource: 'checkin_inputs_v2',
      mlSentiment: { crisisText: { severity: 'high', triggerLayer: 'lexicon', matchedPhrases: ['x'],
        modelUsed: 'lexicon', lexiconVersion: '3' } },
    }));
    await assertFails(addDoc(collection(patient(), 'daily_logs'), {
      patientId: 'p1', therapistId: 't1', timestamp: serverTimestamp(), mlSentiment: 'bad',
    }));
  });
});

describe('default deny', () => {
  it('unknown and server-only collections are closed', async () => {
    await assertFails(getDocs(query(collection(therapist(), 'anomalies'), where('therapistId', '==', 't1'))));
    await assertFails(addDoc(collection(patient(), 'reminders'), { a: 1 }));
    await assertFails(addDoc(collection(therapist(), 'interventions'), { a: 1 }));
    await assertFails(addDoc(collection(therapist(), 'messages'), { a: 1 }));
    await assertFails(getDoc(doc(therapist(), 'alert_cooldowns/p1')));
    await assertFails(getDoc(doc(therapist(), 'push_receipts/x')));
  });
});
