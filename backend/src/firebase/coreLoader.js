'use strict';

/**
 * Loads the shared server logic from functions/src/core (the same code the
 * Cloud Functions run on the Blaze plan).
 *
 * Why a relative require works: functions/src/core and functions/src/logic
 * only use node built-ins and inject every Firebase SDK object, so nothing is
 * resolved from functions/node_modules. The backend passes ITS OWN
 * firebase-admin (FieldValue/Timestamp sentinels must come from the same SDK
 * copy as the Firestore instance). Deployments must ship functions/src next
 * to backend/ (see render.yaml / docs/FREE_DEPLOYMENT.md).
 */

const path = require('path');

const CORE_DIR = path.resolve(__dirname, '..', '..', '..', 'functions', 'src', 'core');

function loadCoreModule() {
  try {
    // eslint-disable-next-line global-require, import/no-dynamic-require
    return require(CORE_DIR);
  } catch (err) {
    const e = new Error(
      `Cannot load shared server logic from ${CORE_DIR}: ${err.message}. ` +
      'The backend must be deployed together with functions/src (repo checkout).'
    );
    e.cause = err;
    throw e;
  }
}

/** Structured console logger compatible with the core's logger interface. */
function createConsoleLogger(prefix = '[functions]') {
  const fmt = (fields) => {
    if (!fields || typeof fields !== 'object') return '';
    try {
      return ` ${JSON.stringify(fields)}`;
    } catch {
      return '';
    }
  };
  return {
    info: (msg, fields) => console.log(`${prefix} ${msg}${fmt(fields)}`),
    warn: (msg, fields) => console.warn(`${prefix} WARN ${msg}${fmt(fields)}`),
    error: (msg, fields) => console.error(`${prefix} ERROR ${msg}${fmt(fields)}`),
  };
}

/**
 * Builds the core with the backend's firebase-admin namespace.
 * @param {typeof import('firebase-admin')} admin initialized namespace
 * @param {object} [overrides] e.g. {messaging, logger} for tests
 */
function createBackendCore(admin, overrides = {}) {
  const { createCore } = loadCoreModule();
  return createCore({
    db: () => admin.firestore(),
    auth: () => admin.auth(),
    messaging: () => admin.messaging(),
    FieldValue: admin.firestore.FieldValue,
    Timestamp: admin.firestore.Timestamp,
    logger: createConsoleLogger(),
    ...overrides,
  });
}

module.exports = { CORE_DIR, loadCoreModule, createBackendCore, createConsoleLogger };
