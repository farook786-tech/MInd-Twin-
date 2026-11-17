'use strict';

/**
 * Account lifecycle cleanup.
 *
 * When a user deletes their Firebase Auth account (AuthService.deleteAccount),
 * clients cannot delete server-owned docs, so this trigger removes the
 * personal profile and every push token for that uid. Without it, the
 * profile (name, email, risk snapshot) would linger and pushes could still be
 * routed to a device the person no longer controls.
 *
 * Clinical records (daily_logs, clinical_assessments, crisis_events, vitals,
 * journal_entries, appointments) are intentionally RETAINED: health-record
 * retention obligations apply and the treating therapist may need them.
 * Erasure of clinical records must go through the clinic's documented
 * data-deletion process, not an automatic trigger.
 */

const functionsV1 = require('firebase-functions/v1');
const { logger } = require('firebase-functions');
const { db } = require('../admin');
const { REGION } = require('../logic/constants');

async function cleanupDeletedUser(uid) {
  const firestore = db();

  const tokens = await firestore.collection('fcm_tokens').where('uid', '==', uid).get();
  const batch = firestore.batch();
  tokens.forEach((doc) => batch.delete(doc.ref));
  batch.delete(firestore.collection('users').doc(uid));
  batch.delete(firestore.collection('alert_cooldowns').doc(uid));
  await batch.commit();

  logger.info('Deleted account cleanup complete', { uid, tokensRemoved: tokens.size });
  return { tokensRemoved: tokens.size };
}

const onAuthUserDeleted = functionsV1
  .region(REGION)
  .auth.user()
  .onDelete((user) => cleanupDeletedUser(user.uid));

module.exports = { onAuthUserDeleted, cleanupDeletedUser };
