'use strict';

/**
 * Account lifecycle cleanup (Cloud Functions / Blaze).
 *
 * When a user deletes their Firebase Auth account (AuthService.deleteAccount),
 * clients cannot delete server-owned docs, so this trigger removes the
 * personal profile and every push token for that uid. Clinical records are
 * intentionally RETAINED (see ../core/triggers.js cleanupDeletedUser).
 *
 * On the free Spark plan there is no Auth trigger; the backend runs the same
 * cleanup from a periodic orphan sweep (backend/src/firebase/orphanSweep.js).
 */

const functionsV1 = require('firebase-functions/v1');
const { REGION } = require('../logic/constants');
const { core } = require('../runtime');

function cleanupDeletedUser(uid) {
  return core().triggers.cleanupDeletedUser(uid);
}

const onAuthUserDeleted = functionsV1
  .region(REGION)
  .auth.user()
  .onDelete((user) => cleanupDeletedUser(user.uid));

module.exports = { onAuthUserDeleted, cleanupDeletedUser };
