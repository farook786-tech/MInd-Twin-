'use strict';

/**
 * Dependency contract of the shared core. Both hosts build one of these from
 * their OWN firebase-admin installation (FieldValue/Timestamp sentinels must
 * come from the same @google-cloud/firestore copy as the Firestore instance):
 *   - Cloud Functions: functions/src/runtime.js
 *   - Backend runner:  backend/src/firebase/functionsCore.js
 *
 * @typedef {object} CoreLogger
 * @property {(msg: string, fields?: object) => void} info
 * @property {(msg: string, fields?: object) => void} warn
 * @property {(msg: string, fields?: object) => void} error
 *
 * @typedef {object} CoreDeps
 * @property {() => FirebaseFirestore.Firestore} db
 * @property {() => import('firebase-admin/auth').Auth} auth
 * @property {() => import('firebase-admin/messaging').Messaging} messaging
 * @property {typeof import('firebase-admin/firestore').FieldValue} FieldValue
 * @property {typeof import('firebase-admin/firestore').Timestamp} Timestamp
 * @property {CoreLogger} logger
 */

const REQUIRED = ['db', 'auth', 'messaging', 'FieldValue', 'Timestamp', 'logger'];

/**
 * @param {CoreDeps} deps
 * @return {CoreDeps}
 */
function checkDeps(deps) {
  if (!deps || typeof deps !== 'object') throw new TypeError('core deps object required');
  for (const k of REQUIRED) {
    if (!deps[k]) throw new TypeError(`core deps.${k} is required`);
  }
  for (const k of ['db', 'auth', 'messaging']) {
    if (typeof deps[k] !== 'function') throw new TypeError(`core deps.${k} must be a function`);
  }
  for (const level of ['info', 'warn', 'error']) {
    if (typeof deps.logger[level] !== 'function') throw new TypeError(`core deps.logger.${level} missing`);
  }
  return deps;
}

module.exports = { checkDeps };
