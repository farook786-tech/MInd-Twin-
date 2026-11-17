'use strict';

/**
 * Free-plan replacement for the onAuthUserDeleted Cloud Function: there is no
 * listener for Firebase Auth deletions, so deleted accounts are cleaned up
 * lazily. The sweep lists every Auth user, finds `users/{uid}` profiles and
 * `fcm_tokens` whose uid no longer exists in Auth, re-confirms each one with
 * auth.getUser() (must fail with auth/user-not-found) and then runs the
 * shared cleanupDeletedUser (profile, tokens, cooldowns; clinical records are
 * retained).
 *
 * Safety: aborts when Auth lists no users, when the Auth listing fails, or
 * when an implausibly large share of profiles looks orphaned (e.g. backend
 * pointed at the wrong project / emulator) unless `force` is set.
 */

async function listAllAuthUids(auth) {
  const uids = new Set();
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const u of page.users) uids.add(u.uid);
    pageToken = page.pageToken;
  } while (pageToken);
  return uids;
}

/**
 * @param {object} p
 * @param {() => FirebaseFirestore.Firestore} p.db
 * @param {() => import('firebase-admin/auth').Auth} p.auth
 * @param {(uid: string) => Promise<object>} p.cleanupDeletedUser
 * @param {object} p.logger
 * @param {boolean} [p.force]
 * @param {boolean} [p.dryRun]
 * @param {number} [p.maxShare] max fraction of profiles that may be removed (default 0.5)
 */
async function sweepOrphanedAccounts({ db, auth, cleanupDeletedUser, logger, force = false, dryRun = false, maxShare = 0.5 }) {
  const authUids = await listAllAuthUids(auth());
  const profiles = await db().collection('users').select().get();
  const tokens = await db().collection('fcm_tokens').select('uid').get();
  const candidates = new Set();
  for (const d of profiles.docs) if (!authUids.has(d.id)) candidates.add(d.id);
  for (const d of tokens.docs) {
    const uid = d.get('uid');
    if (typeof uid === 'string' && uid && !authUids.has(uid)) candidates.add(uid);
  }
  const summary = {
    authUsers: authUids.size, profiles: profiles.size, tokens: tokens.size,
    candidates: candidates.size, cleaned: [], aborted: null, dryRun,
  };
  if (!candidates.size) return summary;
  if (authUids.size === 0) {
    summary.aborted = 'Auth returned no users; refusing to clean up (wrong project or emulator?)';
  } else if (!force && candidates.size > 3 && candidates.size > profiles.size * maxShare) {
    summary.aborted = `${candidates.size} of ${profiles.size} profiles look orphaned; refusing without force`;
  }
  if (summary.aborted) {
    logger.error(`orphan sweep aborted: ${summary.aborted}`, { candidates: candidates.size });
    return summary;
  }
  for (const uid of candidates) {
    try {
      await auth().getUser(uid);
      continue; // exists after all (created during the sweep): keep
    } catch (err) {
      if (!err || err.code !== 'auth/user-not-found') {
        logger.warn('orphan sweep: could not confirm deletion; skipped', { uid, code: err && err.code });
        continue;
      }
    }
    if (!dryRun) await cleanupDeletedUser(uid);
    summary.cleaned.push(uid);
  }
  logger.info('orphan sweep finished', { ...summary, cleaned: summary.cleaned.length });
  return summary;
}

module.exports = { sweepOrphanedAccounts, listAllAuthUids };
