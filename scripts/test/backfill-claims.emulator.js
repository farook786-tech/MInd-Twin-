'use strict';

/**
 * Emulator test for scripts/backfill-claims.js. From the repo root:
 *   firebase emulators:exec --only auth,firestore --project demo-mindtwin \
 *     "node scripts/test/backfill-claims.emulator.js"
 */

const assert = require('node:assert/strict');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('Refusing to run: emulator environment variables are not set.');
  process.exit(2);
}
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-mindtwin';
const { loadAdmin } = require('../_admin');
const { decide } = require('../backfill-claims');

const SCRIPT = path.join(__dirname, '..', 'backfill-claims.js');
const run = (...args) => execFileSync(process.execPath, [SCRIPT, ...args], { env: process.env, encoding: 'utf8' });

async function main() {
  // pure mapping
  assert.equal(decide({ role: 'patient' }, undefined).target, 'patient');
  assert.equal(decide({ role: 'therapist' }, undefined).target, 'therapist_pending');
  assert.equal(decide({ role: 'therapist_pending' }, undefined).target, 'therapist_pending');
  assert.equal(decide({ role: 'therapist' }, 'therapist').target, 'therapist');
  assert.equal(decide({ role: 'patient' }, 'therapist').target, 'therapist', 'never demotes an approved therapist');
  assert.equal(decide({ role: 'admin' }, undefined).target, null);
  assert.equal(decide(null, undefined).target, null);
  for (const r of ['patient', 'therapist', 'therapist_pending', 'x', undefined]) {
    const t = decide({ role: r }, undefined).target;
    assert.notEqual(t, 'therapist', `never promotes (users.role=${r})`);
  }

  const { db, auth } = loadAdmin();
  const mk = async (uid, claims, doc) => {
    await auth.createUser({ uid, email: `${uid}@x.test`, password: 'secret123' });
    if (claims) await auth.setCustomUserClaims(uid, claims);
    if (doc) await db.doc(`users/${uid}`).set(doc);
  };
  await mk('approved', { role: 'therapist' }, { role: 'therapist', status: 'approved', name: 'A' });
  await mk('legacyTher', null, { role: 'therapist', name: 'L' });
  await mk('linkedPat', null, { role: 'patient', therapistId: 'approved', name: 'P' });
  await mk('namePat', null, { role: 'patient', therapistId: 'Dr Somebody', name: 'Q' });
  await mk('adminPat', { admin: true }, { role: 'patient', therapistId: 'approved' });
  await mk('nodoc', null, null);

  const dry = run();
  assert.match(dry, /DRY-RUN/);
  assert.match(dry, /WOULD SET linkedPat/);
  assert.match(dry, /WARN\s+namePat/);
  assert.match(dry, /SKIP\s+nodoc/);
  for (const uid of ['legacyTher', 'linkedPat', 'namePat']) {
    assert.equal(((await auth.getUser(uid)).customClaims || {}).role, undefined, `dry run wrote ${uid}`);
  }

  const out = run('--apply');
  assert.match(out, /"written": 4/, out);
  const role = async (uid) => ((await auth.getUser(uid)).customClaims || {});
  assert.equal((await role('approved')).role, 'therapist');
  assert.equal((await role('legacyTher')).role, 'therapist_pending');
  assert.equal((await role('linkedPat')).role, 'patient');
  assert.equal((await role('namePat')).role, 'patient');
  assert.deepEqual(await role('adminPat'), { admin: true, role: 'patient' });
  assert.equal((await role('nodoc')).role, undefined);

  const again = run('--apply');
  assert.match(again, /"written": 0/, 'idempotent');
  console.log('BACKFILL TEST PASSED');
}

main().then(() => process.exit(0)).catch((err) => {
  console.error('BACKFILL TEST FAILED:', err);
  process.exit(1);
});
