#!/usr/bin/env node
'use strict';

/**
 * Grant (or revoke with --revoke) the clinic-administrator claim `admin: true`.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=backend/config/firebase-service-account.json \
 *     node scripts/make-admin.js <email> [--revoke]
 *
 * Existing claims (e.g. role) are preserved. Admins may call the
 * approveTherapist callable. The user must refresh their ID token afterwards.
 */

const { loadAdmin, validEmail } = require('./_admin');

async function main() {
  const email = process.argv[2];
  const revoke = process.argv.includes('--revoke');
  if (!validEmail(email)) {
    console.error('Usage: node scripts/make-admin.js <email> [--revoke]');
    process.exit(64);
  }
  const { auth, projectId } = loadAdmin();
  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      console.error(`No Firebase Auth user with email ${email} in project ${projectId}.`);
      process.exit(1);
    }
    throw err;
  }
  const claims = { ...(user.customClaims || {}) };
  if (revoke) delete claims.admin;
  else claims.admin = true;
  await auth.setCustomUserClaims(user.uid, claims);
  if (revoke) await auth.revokeRefreshTokens(user.uid);
  console.log(`${revoke ? 'Revoked' : 'Granted'} admin for ${email} (uid ${user.uid}) in ${projectId}.`);
}

main().catch((err) => {
  console.error(`Failed: ${err.message}`);
  process.exit(1);
});
