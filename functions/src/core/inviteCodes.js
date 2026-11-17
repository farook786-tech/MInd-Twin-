'use strict';

/**
 * Firestore-backed invite-code operations (shared core). Firebase SDK values
 * are injected so the same code runs inside Cloud Functions, the backend
 * runner and scripts/approve-therapist.js, each with its own firebase-admin.
 * Every function takes the Firestore / Auth instance explicitly.
 */

const { COLLECTIONS, ROLES } = require('../logic/constants');
const { generateInviteCode } = require('../logic/inviteCode');
const { InviteCodeError } = require('./errors');

const MAX_ATTEMPTS = 10;

/**
 * @param {{FieldValue: typeof import('firebase-admin/firestore').FieldValue}} sdk
 */
function createInviteCodes({ FieldValue }) {
  async function isCodeValidFor(db, code, therapistUid, tx) {
    if (typeof code !== 'string' || !code) return false;
    const ref = db.collection(COLLECTIONS.INVITE_CODES).doc(code);
    const snap = tx ? await tx.get(ref) : await ref.get();
    return snap.exists && snap.get('active') === true && snap.get('therapistId') === therapistUid;
  }

  /**
   * Returns the therapist's active invite code, creating a unique one if
   * missing. Uniqueness is guaranteed by creating invite_codes/{code} inside a
   * transaction that first checks the code does not exist.
   * @param {FirebaseFirestore.Firestore} db
   * @param {string} therapistUid
   * @param {() => string} [generate] injectable for tests
   * @return {Promise<string>}
   */
  async function ensureInviteCode(db, therapistUid, generate = generateInviteCode) {
    const userRef = db.collection(COLLECTIONS.USERS).doc(therapistUid);
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
      const candidate = generate();
      const result = await db.runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        const existing = userSnap.exists ? userSnap.get('inviteCode') : null;
        if (existing && await isCodeValidFor(db, existing, therapistUid, tx)) {
          return { code: existing };
        }
        const codeRef = db.collection(COLLECTIONS.INVITE_CODES).doc(candidate);
        const codeSnap = await tx.get(codeRef);
        if (codeSnap.exists) return { collision: true };
        tx.create(codeRef, {
          therapistId: therapistUid,
          active: true,
          createdAt: FieldValue.serverTimestamp(),
        });
        if (existing) {
          const oldRef = db.collection(COLLECTIONS.INVITE_CODES).doc(existing);
          const oldSnap = await tx.get(oldRef);
          if (oldSnap.exists && oldSnap.get('therapistId') === therapistUid) {
            tx.update(oldRef, { active: false, deactivatedAt: FieldValue.serverTimestamp() });
          }
        }
        tx.set(userRef, { inviteCode: candidate }, { merge: true });
        return { code: candidate };
      });
      if (result.code) return result.code;
    }
    throw new InviteCodeError('internal', 'could not allocate a unique invite code');
  }

  /**
   * Resolves an invite code to an approved therapist inside a transaction.
   * @return {Promise<{therapistId: string, therapistName: string}>}
   */
  async function resolveInviteCode(db, tx, code) {
    const codeSnap = await tx.get(db.collection(COLLECTIONS.INVITE_CODES).doc(code));
    if (!codeSnap.exists || codeSnap.get('active') !== true) {
      throw new InviteCodeError('not-found', 'Invite code not found or no longer active.');
    }
    const therapistId = codeSnap.get('therapistId');
    if (typeof therapistId !== 'string' || !therapistId) {
      throw new InviteCodeError('not-found', 'Invite code not found or no longer active.');
    }
    const therapistSnap = await tx.get(db.collection(COLLECTIONS.USERS).doc(therapistId));
    if (!therapistSnap.exists ||
        therapistSnap.get('role') !== ROLES.THERAPIST ||
        therapistSnap.get('status') !== 'approved' ||
        therapistSnap.get('inviteCode') !== code) {
      throw new InviteCodeError('not-found', 'Invite code not found or no longer active.');
    }
    const therapistName = String(therapistSnap.get('name') || 'Your therapist');
    return { therapistId, therapistName };
  }

  /**
   * Approves a therapist: users doc -> invite code -> custom claim (in this
   * order so a partial failure is fixed by simply re-running).
   * Refuses to promote anyone whose users doc is not a therapist / pending
   * therapist (prevents turning a patient into a therapist by mistake).
   * @param {FirebaseFirestore.Firestore} db
   * @param {import('firebase-admin/auth').Auth} auth
   * @param {string} therapistUid
   * @param {string} approvedBy uid of the admin, or 'script:<user>'
   * @return {Promise<string>} invite code
   */
  async function approveTherapistAccount(db, auth, therapistUid, approvedBy) {
    let userRecord;
    try {
      userRecord = await auth.getUser(therapistUid);
    } catch (err) {
      if (err && err.code === 'auth/user-not-found') {
        throw new InviteCodeError('not-found', 'No such user.');
      }
      throw err;
    }
    const userRef = db.collection(COLLECTIONS.USERS).doc(therapistUid);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      const role = snap.exists ? snap.get('role') : null;
      if (role !== ROLES.THERAPIST_PENDING && role !== ROLES.THERAPIST) {
        throw new InviteCodeError('failed-precondition',
          `User is not a therapist applicant (role=${JSON.stringify(role)}). ` +
          'They must sign up as a therapist (registerTherapist) first.');
      }
      tx.set(userRef, {
        role: ROLES.THERAPIST,
        status: 'approved',
        approvedAt: FieldValue.serverTimestamp(),
        approvedBy,
      }, { merge: true });
    });
    const code = await ensureInviteCode(db, therapistUid);
    const claims = { ...(userRecord.customClaims || {}), role: ROLES.THERAPIST };
    await auth.setCustomUserClaims(therapistUid, claims);
    return code;
  }

  return { ensureInviteCode, resolveInviteCode, approveTherapistAccount };
}

module.exports = { createInviteCodes, InviteCodeError, MAX_ATTEMPTS };
