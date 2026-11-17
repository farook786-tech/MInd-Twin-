'use strict';

/**
 * Shared bootstrap for admin scripts. Loads firebase-admin from functions/
 * (run `npm ci` in functions/ first) so both use the same module instance.
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS must point at a service-account
 * JSON (e.g. backend/config/firebase-service-account.json). The key is never
 * printed.
 */

const path = require('node:path');
const fs = require('node:fs');
const { createRequire } = require('node:module');

const FUNCTIONS_DIR = path.join(__dirname, '..', 'functions');
const fnRequire = createRequire(path.join(FUNCTIONS_DIR, 'package.json'));

function loadAdmin() {
  const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!usingEmulator) {
    if (!credPath) {
      throw new Error('Set GOOGLE_APPLICATION_CREDENTIALS to the service-account JSON path ' +
        '(e.g. backend/config/firebase-service-account.json).');
    }
    if (!fs.existsSync(credPath)) {
      throw new Error(`GOOGLE_APPLICATION_CREDENTIALS file not found: ${credPath}`);
    }
  }
  let app;
  try {
    app = fnRequire('firebase-admin/app');
  } catch {
    throw new Error('firebase-admin not installed. Run `npm ci` in functions/ first.');
  }
  const { getFirestore } = fnRequire('firebase-admin/firestore');
  const { getAuth } = fnRequire('firebase-admin/auth');
  const projectId = process.env.GCLOUD_PROJECT || 'mindtwin-60879';
  if (!app.getApps().length) {
    app.initializeApp(usingEmulator ?
      { projectId } :
      { credential: app.applicationDefault(), projectId });
  }
  return { db: getFirestore(), auth: getAuth(), fnRequire, projectId };
}

function validEmail(e) {
  return typeof e === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);
}

module.exports = { loadAdmin, validEmail, FUNCTIONS_DIR };
