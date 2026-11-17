#!/usr/bin/env node
'use strict';

/**
 * One-off migration: give every existing Firebase Auth user the `role` custom
 * claim that firestore.rules require. DRY-RUN by default.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=backend/config/firebase-service-account.json \
 *     node scripts/backfill-claims.js            # report only
 *     node scripts/backfill-claims.js --apply    # write claims
 *
 * Mapping (from users/{uid}.role):
 *   patient                      -> 'patient' (the therapist link is checked and
 *                                   reported; unresolved links are listed so ops can
 *                                   re-link via invite code — the claim is set anyway)
 *   therapist / therapist_pending-> 'therapist_pending', UNLESS the user already has
 *                                   claim role 'therapist' (approved via
 *                                   scripts/approve-therapist.js), which is kept.
 *   anything else / no users doc -> skipped and reported.
 * NEVER promotes anyone to 'therapist'; approval stays a manual, explicit step.
 * Other claims (e.g. admin) are preserved. Users must refresh their ID token.
 */

const { loadAdmin } = require('./_admin');

const APPLY = process.argv.includes('--apply');

function decide(userDoc, currentRole) {
  const role = userDoc ? userDoc.role : undefined;
  if (currentRole === 'therapist') {
    // Already approved through the script/callable: never touch.
    return { target: 'therapist', reason: 'already approved therapist (kept)' };
  }
  if (role === 'patient') return { target: 'patient', reason: 'users.role=patient' };
  if (role === 'therapist' || role === 'therapist_pending') {
    return { target: 'therapist_pending', reason: `users.role=${role}; needs approve-therapist.js` };
  }
  return { target: null, reason: userDoc ? `unknown users.role=${JSON.stringify(role)}` : 'no users doc' };
}

async function main() {
  const { db, auth, projectId } = loadAdmin();
  console.log(`${APPLY ? 'APPLY' : 'DRY-RUN'} on project ${projectId}`);

  const summary = {
    scanned: 0, unchanged: 0, toPatient: 0, toTherapistPending: 0, keptTherapist: 0,
    skipped: 0, unresolvedTherapistLink: 0, written: 0, errors: 0,
  };
  const therapistCache = new Map();
  async function therapistApproved(tid) {
    if (typeof tid !== 'string' || !tid || tid.includes('/')) return false;
    if (!therapistCache.has(tid)) {
      const snap = await db.collection('users').doc(tid).get();
      therapistCache.set(tid, snap.exists && snap.get('role') === 'therapist' && snap.get('status') === 'approved');
    }
    return therapistCache.get(tid);
  }

  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    pageToken = page.pageToken;
    for (const user of page.users) {
      summary.scanned += 1;
      const claims = user.customClaims || {};
      const snap = await db.collection('users').doc(user.uid).get();
      const data = snap.exists ? snap.data() : null;
      const { target, reason } = decide(data, claims.role);
      const label = `${user.uid} <${user.email || 'no-email'}>`;

      if (!target) {
        summary.skipped += 1;
        console.log(`SKIP      ${label}: ${reason}`);
        continue;
      }
      if (target === 'patient' && !(await therapistApproved(data.therapistId))) {
        summary.unresolvedTherapistLink += 1;
        console.log(`WARN      ${label}: therapistId ${JSON.stringify(data.therapistId)} is not an approved ` +
          'therapist; patient must re-link with an invite code (joinTherapist)');
      }
      if (target === 'therapist') summary.keptTherapist += 1;
      if (claims.role === target) {
        summary.unchanged += 1;
        continue;
      }
      if (target === 'patient') summary.toPatient += 1;
      if (target === 'therapist_pending') summary.toTherapistPending += 1;
      console.log(`${APPLY ? 'SET' : 'WOULD SET'} ${label}: role ${JSON.stringify(claims.role)} -> ` +
        `${target} (${reason})`);
      if (APPLY) {
        try {
          await auth.setCustomUserClaims(user.uid, { ...claims, role: target });
          summary.written += 1;
        } catch (err) {
          summary.errors += 1;
          console.error(`ERROR     ${label}: ${err.message}`);
        }
      }
    }
  } while (pageToken);

  console.log('\nSummary:', JSON.stringify(summary, null, 2));
  if (!APPLY) console.log('Dry run only. Re-run with --apply to write claims.');
  if (summary.errors) process.exitCode = 1;
}

if (require.main === module) {
  main().catch((err) => {
    console.error(`Failed: ${err.message}`);
    process.exit(1);
  });
}

module.exports = { decide };
