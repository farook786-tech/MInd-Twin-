'use strict';

/**
 * Cloud Functions (Blaze) wrappers for the callables. The logic lives in
 * ./core/callables.js and is shared with the backend's POST /api/callable/:name
 * (Spark plan, see docs/FREE_DEPLOYMENT.md).
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { core, logger } = require('./runtime');
const { runCallable } = require('./core/callables');

const CALL_OPTS = { cors: false };

/** Adapts a core callable to onCall, converting CallableError -> HttpsError. */
function wrap(name) {
  return onCall(CALL_OPTS, async (request) => {
    const authContext = request.auth && request.auth.uid ?
      { uid: request.auth.uid, token: request.auth.token || {} } : null;
    try {
      return await runCallable(name, core().callables[name], authContext, request.data, logger);
    } catch (err) {
      // runCallable only rejects with CallableError (unexpected errors are
      // already logged and replaced by 'internal').
      throw new HttpsError(err.code || 'internal', err.message);
    }
  });
}

module.exports = {
  registerPatient: wrap('registerPatient'),
  registerTherapist: wrap('registerTherapist'),
  joinTherapist: wrap('joinTherapist'),
  approveTherapist: wrap('approveTherapist'),
  getMyInviteCode: wrap('getMyInviteCode'),
  restampTherapistId: (patientId, newTherapistId) =>
    core().callables.restampTherapistId(patientId, newTherapistId),
};
