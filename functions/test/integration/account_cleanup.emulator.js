'use strict';
// Run: firebase emulators:exec --only firestore --project demo-mindtwin "node functions/test/integration/account_cleanup.emulator.js"
const assert = require('node:assert');
const { cleanupDeletedUser } = require('../../src/triggers/accounts');
const { db } = require('../../src/admin');

(async () => {
  const f = db();
  await f.doc('users/u1').set({ role: 'patient', name: 'A' });
  await f.doc('fcm_tokens/t1').set({ uid: 'u1' });
  await f.doc('fcm_tokens/t2').set({ uid: 'u1' });
  await f.doc('fcm_tokens/t3').set({ uid: 'other' });
  await f.doc('daily_logs/l1').set({ patientId: 'u1' });
  const r = await cleanupDeletedUser('u1');
  assert.strictEqual(r.tokensRemoved, 2);
  assert.strictEqual((await f.doc('users/u1').get()).exists, false);
  assert.strictEqual((await f.doc('fcm_tokens/t3').get()).exists, true, 'other users tokens kept');
  assert.strictEqual((await f.doc('daily_logs/l1').get()).exists, true, 'clinical records retained');
  console.log('account cleanup: OK');
})().catch((e) => { console.error(e); process.exit(1); });
