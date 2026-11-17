'use strict';

/**
 * Core logic of the callables (docs/DATA_MODEL.md "Callable functions").
 * Each callable is `async (authContext, data) => result` where authContext is
 * `{uid, token}` (token = decoded Firebase ID token incl. custom claims) or
 * null. Failures are thrown as CallableError (see ./errors.js); anything else
 * is unexpected and reported as 'internal' by runCallable().
 *
 * Hosts: functions/src/callables.js (onCall wrappers, Blaze) and
 * backend/src/firebase/callableRouter.js (POST /api/callable/:name, Spark).
 */

const { COLLECTIONS, ROLES } = require('../logic/constants');
const { normalizeInviteCode } = require('../logic/inviteCode');
const {
  validateName, validateOptionalText, validateUid, requireObject,
} = require('../logic/validation');
const { CallableError, toCallableError } = require('./errors');
const { createInviteCodes } = require('./inviteCodes');

// Collections whose documents carry a denormalised therapistId that must
// follow the patient when they switch therapist (rules rely on it).
const RESTAMP_COLLECTIONS = [
  COLLECTIONS.DAILY_LOGS,
  COLLECTIONS.ASSESSMENTS,
  COLLECTIONS.CRISIS_EVENTS,
  COLLECTIONS.VITALS,
  COLLECTIONS.JOURNAL_ENTRIES,
];

const CALLABLE_NAMES = Object.freeze([
  'registerPatient',
  'registerTherapist',
  'joinTherapist',
  'approveTherapist',
  'getMyInviteCode',
]);

function requireAuth(authContext) {
  if (!authContext || typeof authContext.uid !== 'string' || !authContext.uid) {
    throw new CallableError('permission-denied', 'Sign in first.');
  }
  return { uid: authContext.uid, token: authContext.token || {} };
}

function parseInviteCode(data) {
  const code = normalizeInviteCode(data.inviteCode);
  if (!code) throw new CallableError('invalid-argument', 'inviteCode must be an 8-character invite code.');
  return code;
}

/**
 * Runs a core callable and normalises failures: resolves with the result or
 * rejects with a CallableError. Unexpected errors are logged with their stack
 * and replaced by a generic 'internal' error (no internals leak to clients).
 */
async function runCallable(name, fn, authContext, data, logger) {
  try {
    return await fn(authContext, data);
  } catch (err) {
    const mapped = toCallableError(err);
    if (mapped) throw mapped;
    logger.error(`${name} failed`, { error: err && err.message, stack: err && err.stack });
    throw new CallableError('internal', 'Unexpected error. Please try again.');
  }
}

/**
 * @param {import('./deps').CoreDeps} deps
 */
function createCallables({ db, auth, FieldValue, logger }) {
  const { ensureInviteCode, resolveInviteCode, approveTherapistAccount } =
    createInviteCodes({ FieldValue });

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
  async function registerPatient(authContext, rawData) {
    const { uid, token } = requireAuth(authContext);
    const data = requireObject(rawData);
    const name = validateName(data.name);
    const code = parseInviteCode(data);
    if (token.role && token.role !== ROLES.PATIENT) {
      throw new CallableError('failed-precondition', 'This account is not a patient account.');
    }
    const userRef = db().collection(COLLECTIONS.USERS).doc(uid);
    const result = await db().runTransaction(async (tx) => {
      const link = await resolveInviteCode(db(), tx, code);
      if (link.therapistId === uid) {
        throw new CallableError('failed-precondition', 'You cannot register with your own invite code.');
      }
      const snap = await tx.get(userRef);
      const role = snap.exists ? snap.get('role') : undefined;
      if (role && role !== ROLES.PATIENT) {
        throw new CallableError('failed-precondition', 'This account is not a patient account.');
      }
      const currentTherapist = snap.exists ? snap.get('therapistId') : undefined;
      if (role === ROLES.PATIENT && currentTherapist && currentTherapist !== link.therapistId) {
        throw new CallableError('failed-precondition',
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
  }

  /** registerTherapist {name, licenseNumber?, specialty?} -> {status:'pending'} */
  async function registerTherapist(authContext, rawData) {
    const { uid, token } = requireAuth(authContext);
    const data = requireObject(rawData);
    const name = validateName(data.name);
    const licenseNumber = validateOptionalText(data.licenseNumber, 'licenseNumber', 64);
    const specialty = validateOptionalText(data.specialty, 'specialty', 100);
    if (token.role === ROLES.PATIENT) {
      throw new CallableError('failed-precondition', 'A patient account cannot register as a therapist.');
    }
    if (token.role === ROLES.THERAPIST) {
      throw new CallableError('failed-precondition', 'This therapist account is already approved.');
    }
    const userRef = db().collection(COLLECTIONS.USERS).doc(uid);
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      const role = snap.exists ? snap.get('role') : undefined;
      if (role === ROLES.PATIENT) {
        throw new CallableError('failed-precondition', 'A patient account cannot register as a therapist.');
      }
      if (role === ROLES.THERAPIST && snap.get('status') === 'approved') {
        throw new CallableError('failed-precondition', 'This therapist account is already approved.');
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
  }

  /** joinTherapist {inviteCode} -> {therapistId, therapistName} */
  async function joinTherapist(authContext, rawData) {
    const { uid, token } = requireAuth(authContext);
    const data = requireObject(rawData);
    const code = parseInviteCode(data);
    if (token.role !== ROLES.PATIENT) {
      throw new CallableError('permission-denied', 'Only patients can join a therapist.');
    }
    const userRef = db().collection(COLLECTIONS.USERS).doc(uid);
    const outcome = await db().runTransaction(async (tx) => {
      const link = await resolveInviteCode(db(), tx, code);
      if (link.therapistId === uid) {
        throw new CallableError('failed-precondition', 'You cannot join your own invite code.');
      }
      const snap = await tx.get(userRef);
      if (!snap.exists || snap.get('role') !== ROLES.PATIENT) {
        throw new CallableError('failed-precondition', 'Patient profile missing. Call registerPatient first.');
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
  }

  /** approveTherapist {therapistUid} -> {inviteCode} (admin only) */
  async function approveTherapist(authContext, rawData) {
    const { uid, token } = requireAuth(authContext);
    if (token.admin !== true) {
      throw new CallableError('permission-denied', 'Administrator access required.');
    }
    const data = requireObject(rawData);
    const therapistUid = validateUid(data.therapistUid, 'therapistUid');
    const inviteCode = await approveTherapistAccount(db(), auth(), therapistUid, uid);
    logger.info('therapist approved', { therapistUid, approvedBy: uid });
    return { inviteCode };
  }

  /** getMyInviteCode {} -> {inviteCode} (approved therapist only) */
  async function getMyInviteCode(authContext) {
    const { uid, token } = requireAuth(authContext);
    if (token.role !== ROLES.THERAPIST) {
      throw new CallableError('permission-denied', 'Only approved therapists have an invite code.');
    }
    const snap = await db().collection(COLLECTIONS.USERS).doc(uid).get();
    if (!snap.exists || snap.get('status') !== 'approved' || snap.get('role') !== ROLES.THERAPIST) {
      throw new CallableError('failed-precondition', 'Therapist account is not approved.');
    }
    const inviteCode = await ensureInviteCode(db(), uid);
    return { inviteCode };
  }

  return {
    registerPatient,
    registerTherapist,
    joinTherapist,
    approveTherapist,
    getMyInviteCode,
    restampTherapistId,
  };
}

module.exports = { createCallables, runCallable, CALLABLE_NAMES, RESTAMP_COLLECTIONS };
