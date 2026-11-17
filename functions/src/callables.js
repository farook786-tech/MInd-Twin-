'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions/v2');
const { FieldValue } = require('firebase-admin/firestore');
const { db, auth } = require('./admin');
const { COLLECTIONS, ROLES } = require('./logic/constants');
const { normalizeInviteCode } = require('./logic/inviteCode');
const {
  validateName, validateOptionalText, validateUid, requireObject,
} = require('./logic/validation');
const {
  InviteCodeError, ensureInviteCode, resolveInviteCode, approveTherapistAccount,
} = require('./inviteCodes');

// Collections whose documents carry a denormalised therapistId that must
// follow the patient when they switch therapist (rules rely on it).
const RESTAMP_COLLECTIONS = [
  COLLECTIONS.DAILY_LOGS,
  COLLECTIONS.ASSESSMENTS,
  COLLECTIONS.CRISIS_EVENTS,
  COLLECTIONS.VITALS,
  COLLECTIONS.JOURNAL_ENTRIES,
];

const CALL_OPTS = { cors: false };

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('permission-denied', 'Sign in first.');
  }
  return { uid: request.auth.uid, token: request.auth.token || {} };
}

/** Converts validation / invite errors into contract error codes. */
function wrap(name, handler) {
  return onCall(CALL_OPTS, async (request) => {
    try {
      return await handler(request);
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      if (err instanceof InviteCodeError) throw new HttpsError(err.code, err.message);
      if (err && err.name === 'ValidationError') throw new HttpsError('invalid-argument', err.message);
      logger.error(`${name} failed`, { error: err && err.message, stack: err && err.stack });
      throw new HttpsError('internal', 'Unexpected error. Please try again.');
    }
  });
}

function parseInviteCode(data) {
  const code = normalizeInviteCode(data.inviteCode);
  if (!code) throw new HttpsError('invalid-argument', 'inviteCode must be an 8-character invite code.');
  return code;
}

async function setRoleClaim(uid, role) {
  const user = await auth().getUser(uid);
  const claims = { ...(user.customClaims || {}), role };
  await auth().setCustomUserClaims(uid, claims);
}

async function restampTherapistId(patientId, newTherapistId) {
  const writer = db().bulkWriter();
  let count = 0;
  for (const col of RESTAMP_COLLECTIONS) {
    const snap = await db().collection(col).where('patientId', '==', patientId).get();
    for (const doc of snap.docs) {
      if (doc.get('therapistId') !== newTherapistId) {
        writer.update(doc.ref, { therapistId: newTherapistId });
        count += 1;
      }
    }
  }
  await writer.close();
  return count;
}

/** registerPatient {name, inviteCode} -> {therapistId, therapistName} */
const registerPatient = wrap('registerPatient', async (request) => {
  const { uid, token } = requireAuth(request);
  const data = requireObject(request.data);
  const name = validateName(data.name);
  const code = parseInviteCode(data);
  if (token.role && token.role !== ROLES.PATIENT) {
    throw new HttpsError('failed-precondition', 'This account is not a patient account.');
  }
  const userRef = db().collection(COLLECTIONS.USERS).doc(uid);
  const result = await db().runTransaction(async (tx) => {
    const link = await resolveInviteCode(db(), tx, code);
    if (link.therapistId === uid) {
      throw new HttpsError('failed-precondition', 'You cannot register with your own invite code.');
    }
    const snap = await tx.get(userRef);
    const role = snap.exists ? snap.get('role') : undefined;
    if (role && role !== ROLES.PATIENT) {
      throw new HttpsError('failed-precondition', 'This account is not a patient account.');
    }
    const currentTherapist = snap.exists ? snap.get('therapistId') : undefined;
    if (role === ROLES.PATIENT && currentTherapist && currentTherapist !== link.therapistId) {
      throw new HttpsError('failed-precondition',
        'Already registered with a therapist. Use joinTherapist to switch.');
    }
    tx.set(userRef, {
      role: ROLES.PATIENT,
      therapistId: link.therapistId,
      therapistName: link.therapistName,
      name,
      ...(token.email ? { email: token.email } : {}),
      ...(snap.exists && snap.get('createdAt') ? {} : { createdAt: FieldValue.serverTimestamp() }),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return link;
  });
  await setRoleClaim(uid, ROLES.PATIENT);
  logger.info('patient registered', { uid, therapistId: result.therapistId });
  return { therapistId: result.therapistId, therapistName: result.therapistName };
});

/** registerTherapist {name, licenseNumber?, specialty?} -> {status:'pending'} */
const registerTherapist = wrap('registerTherapist', async (request) => {
  const { uid, token } = requireAuth(request);
  const data = requireObject(request.data);
  const name = validateName(data.name);
  const licenseNumber = validateOptionalText(data.licenseNumber, 'licenseNumber', 64);
  const specialty = validateOptionalText(data.specialty, 'specialty', 100);
  if (token.role === ROLES.PATIENT) {
    throw new HttpsError('failed-precondition', 'A patient account cannot register as a therapist.');
  }
  if (token.role === ROLES.THERAPIST) {
    throw new HttpsError('failed-precondition', 'This therapist account is already approved.');
  }
  const userRef = db().collection(COLLECTIONS.USERS).doc(uid);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const role = snap.exists ? snap.get('role') : undefined;
    if (role === ROLES.PATIENT) {
      throw new HttpsError('failed-precondition', 'A patient account cannot register as a therapist.');
    }
    if (role === ROLES.THERAPIST && snap.get('status') === 'approved') {
      throw new HttpsError('failed-precondition', 'This therapist account is already approved.');
    }
    tx.set(userRef, {
      role: ROLES.THERAPIST_PENDING,
      status: 'pending',
      name,
      ...(licenseNumber !== null ? { licenseNumber } : {}),
      ...(specialty !== null ? { specialty } : {}),
      ...(token.email ? { email: token.email } : {}),
      ...(snap.exists && snap.get('createdAt') ? {} : { createdAt: FieldValue.serverTimestamp() }),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  await setRoleClaim(uid, ROLES.THERAPIST_PENDING);
  logger.info('therapist registration pending approval', { uid });
  return { status: 'pending' };
});

/** joinTherapist {inviteCode} -> {therapistId, therapistName} */
const joinTherapist = wrap('joinTherapist', async (request) => {
  const { uid, token } = requireAuth(request);
  const data = requireObject(request.data);
  const code = parseInviteCode(data);
  if (token.role !== ROLES.PATIENT) {
    throw new HttpsError('permission-denied', 'Only patients can join a therapist.');
  }
  const userRef = db().collection(COLLECTIONS.USERS).doc(uid);
  const outcome = await db().runTransaction(async (tx) => {
    const link = await resolveInviteCode(db(), tx, code);
    if (link.therapistId === uid) {
      throw new HttpsError('failed-precondition', 'You cannot join your own invite code.');
    }
    const snap = await tx.get(userRef);
    if (!snap.exists || snap.get('role') !== ROLES.PATIENT) {
      throw new HttpsError('failed-precondition', 'Patient profile missing. Call registerPatient first.');
    }
    const previous = snap.get('therapistId') || null;
    tx.set(userRef, {
      therapistId: link.therapistId,
      therapistName: link.therapistName,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ...link, previous };
  });
  // Old therapist must lose access to history; new one gains it. Always run
  // (it only touches docs still carrying another therapistId) so that a retry
  // after a partial failure completes the migration.
  const n = await restampTherapistId(uid, outcome.therapistId);
  logger.info('patient linked to therapist', {
    uid, from: outcome.previous, to: outcome.therapistId, restamped: n,
  });
  return { therapistId: outcome.therapistId, therapistName: outcome.therapistName };
});

/** approveTherapist {therapistUid} -> {inviteCode} (admin only) */
const approveTherapist = wrap('approveTherapist', async (request) => {
  const { uid, token } = requireAuth(request);
  if (token.admin !== true) {
    throw new HttpsError('permission-denied', 'Administrator access required.');
  }
  const data = requireObject(request.data);
  const therapistUid = validateUid(data.therapistUid, 'therapistUid');
  const inviteCode = await approveTherapistAccount(db(), auth(), therapistUid, uid);
  logger.info('therapist approved', { therapistUid, approvedBy: uid });
  return { inviteCode };
});

/** getMyInviteCode {} -> {inviteCode} (approved therapist only) */
const getMyInviteCode = wrap('getMyInviteCode', async (request) => {
  const { uid, token } = requireAuth(request);
  if (token.role !== ROLES.THERAPIST) {
    throw new HttpsError('permission-denied', 'Only approved therapists have an invite code.');
  }
  const snap = await db().collection(COLLECTIONS.USERS).doc(uid).get();
  if (!snap.exists || snap.get('status') !== 'approved' || snap.get('role') !== ROLES.THERAPIST) {
    throw new HttpsError('failed-precondition', 'Therapist account is not approved.');
  }
  const inviteCode = await ensureInviteCode(db(), uid);
  return { inviteCode };
});

module.exports = {
  registerPatient,
  registerTherapist,
  joinTherapist,
  approveTherapist,
  getMyInviteCode,
  restampTherapistId,
};
