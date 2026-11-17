const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

let initError = null;

/**
 * Returns the initialized firebase-admin namespace, or null when no
 * credentials are available. Initializes once and is shared by the
 * notification service and ID-token verification.
 *
 * Production (Render): GOOGLE_APPLICATION_CREDENTIALS_JSON holds the service
 * account as raw JSON or base64. Local dev: GOOGLE_APPLICATION_CREDENTIALS
 * points to the JSON file.
 */
function getFirebaseAdmin() {
  if (admin.apps.length) return admin;
  if (initError) return null;

  try {
    const inlineJson = process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON;
    const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    let serviceAccount = null;
    if (inlineJson) {
      const raw = inlineJson.trim();
      serviceAccount = JSON.parse(
        raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8')
      );
    } else if (credentialsPath) {
      const resolvedPath = path.resolve(process.cwd(), credentialsPath);
      serviceAccount = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
    }

    if (serviceAccount) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: serviceAccount.project_id,
      });
    } else {
      admin.initializeApp();
    }
    return admin;
  } catch (error) {
    initError = error;
    console.warn('Firebase Admin SDK not initialized:', error.message);
    return null;
  }
}

module.exports = { getFirebaseAdmin };
