'use strict';

/**
 * Transport-neutral errors for the shared core (functions/src/core).
 *
 * The core never imports firebase-functions: the Cloud Functions wrappers turn
 * a CallableError into an HttpsError, and the backend's /api/callable route
 * turns it into an HTTP status + {error: {code, message}}.
 */

const CALLABLE_ERROR_CODES = Object.freeze([
  'invalid-argument',
  'unauthenticated',
  'permission-denied',
  'not-found',
  'already-exists',
  'failed-precondition',
  'resource-exhausted',
  'unavailable',
  'deadline-exceeded',
  'internal',
]);

class CallableError extends Error {
  /**
   * @param {string} code one of CALLABLE_ERROR_CODES (unknown -> 'internal')
   * @param {string} message safe to show to the end user
   */
  constructor(code, message) {
    super(message);
    this.name = 'CallableError';
    this.code = CALLABLE_ERROR_CODES.includes(code) ? code : 'internal';
  }
}

/** Invite-code failures ('not-found' | 'failed-precondition' | 'internal'). */
class InviteCodeError extends CallableError {
  constructor(code, message) {
    super(code, message);
    this.name = 'InviteCodeError';
  }
}

/**
 * Maps a thrown value to a CallableError, or null when it is unexpected (a
 * bug or infrastructure failure the caller must log and report as internal).
 * ValidationError (logic/validation.js) is matched by name so this module
 * stays dependency free.
 * @param {unknown} err
 * @return {CallableError|null}
 */
function toCallableError(err) {
  if (err instanceof CallableError) return err;
  if (err && err.name === 'ValidationError') return new CallableError('invalid-argument', err.message);
  return null;
}

module.exports = {
  CALLABLE_ERROR_CODES,
  CallableError,
  InviteCodeError,
  toCallableError,
};
