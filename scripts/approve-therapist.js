#!/usr/bin/env node
'use strict';

/**
 * Approve a therapist account and print their invite code.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=backend/config/firebase-service-account.json \
 *     node scripts/approve-therapist.js <email>
 *
 * Sets custom claim role=therapist (other claims preserved), users/{uid}
 * role=therapist + status=approved, and creates a unique invite code.
 * Refuses accounts whose users doc is not a therapist applicant (the person
 * must have signed up in the therapist app, which calls registerTherapist).
 * The therapist must sign out/in (or force-refresh the ID token) afterwards.
 */

const path = require('node:path');
const os = require('node:os');
const { loadAdmin, validEmail, FUNCTIONS_DIR } = require('./_admin');

async function main() {
  const email = process.argv[2];
  if (!validEmail(email)) {
    console.error('Usage: node scripts/approve-therapist.js <email>');
    process.exit(64);
  }
  const { db, auth, projectId } = loadAdmin();
  const { approveTherapistAccount } = require(path.join(FUNCTIONS_DIR, 'src', 'inviteCodes.js'));

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
  if (user.disabled) {
    console.error(`User ${email} is disabled; refusing to approve.`);
    process.exit(1);
  }
  const approvedBy = `script:${os.userInfo().username}`;
  const code = await approveTherapistAccount(db, auth, user.uid, approvedBy);
  console.log(`Approved therapist ${email} (uid ${user.uid}) in ${projectId}.`);
  console.log(`Invite code: ${code}`);
  console.log('The therapist must sign out and back in (or refresh their ID token) to get the new role.');
}

main().catch((err) => {
  console.error(`Failed: ${err.message}`);
  process.exit(1);
});
