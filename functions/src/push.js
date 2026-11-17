'use strict';

const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions/v2');
const { db, messaging } = require('./admin');
const { COLLECTIONS, CHANNELS } = require('./logic/constants');
const { classifySendErrors } = require('./logic/pushErrors');

const RECEIPT_STALE_MS = 5 * 60 * 1000;
const MULTICAST_LIMIT = 500;

/**
 * Exactly-once-ish guard for pushes. Claims push_receipts/{key}:
 *  - 'sent'                 -> return false (already delivered; retry is a no-op)
 *  - 'sending' (< 5 min)    -> throw so the platform retries later (another
 *                              invocation is in flight or crashed mid-send)
 *  - 'sending' (stale)/none -> claim and return true
 * At-least-once is preferred over lost alerts: a crash between FCM send and
 * marking 'sent' may produce one duplicate after the stale window.
 */
async function claimReceipt(key) {
  const ref = db().collection(COLLECTIONS.PUSH_RECEIPTS).doc(key);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    if (snap.exists) {
      const d = snap.data();
      if (d.status === 'sent') return false;
      const claimedAt = d.claimedAt && d.claimedAt.toMillis ? d.claimedAt.toMillis() : 0;
      if (d.status === 'sending' && now - claimedAt < RECEIPT_STALE_MS) {
        throw new Error(`push receipt ${key} is being processed; retry later`);
      }
    }
    tx.set(ref, {
      status: 'sending',
      claimedAt: Timestamp.fromMillis(now),
      attempts: FieldValue.increment(1),
    }, { merge: true });
    return true;
  });
}

async function markReceipt(key, fields) {
  await db().collection(COLLECTIONS.PUSH_RECEIPTS).doc(key).set(fields, { merge: true });
}

async function releaseReceipt(key) {
  await db().collection(COLLECTIONS.PUSH_RECEIPTS).doc(key).delete();
}

function stringifyData(data) {
  const out = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v === undefined || v === null) continue;
    out[k] = String(v);
  }
  return out;
}

/**
 * Sends a push to every registered device of `uid`.
 * @param {object} p
 * @param {string} p.uid recipient
 * @param {'patient'|'therapist'|null} p.app only tokens registered by this app
 * @param {string} p.channelId Android channel (contract)
 * @param {string} p.title
 * @param {string} p.body
 * @param {Object<string, string>} p.data
 * @param {string} p.receiptKey deterministic idempotency key
 * @return {Promise<{skipped?: boolean, tokens: number, success: number, failure: number}>}
 */
async function sendPushToUser({ uid, app, channelId, title, body, data, receiptKey }) {
  if (typeof uid !== 'string' || !uid) {
    logger.error('sendPushToUser: missing recipient uid', { receiptKey });
    return { tokens: 0, success: 0, failure: 0 };
  }
  const claimed = await claimReceipt(receiptKey);
  if (!claimed) {
    logger.info('push already sent; skipping duplicate', { receiptKey });
    return { skipped: true, tokens: 0, success: 0, failure: 0 };
  }

  let tokenDocs;
  try {
    const snap = await db().collection(COLLECTIONS.FCM_TOKENS).where('uid', '==', uid).get();
    tokenDocs = snap.docs.filter((d) => {
      const tokenApp = d.get('app');
      return !app || !tokenApp || tokenApp === app;
    });
  } catch (err) {
    await releaseReceipt(receiptKey);
    throw err;
  }

  const critical = channelId === CHANNELS.CLINICAL_CRITICAL;
  if (!tokenDocs.length) {
    (critical ? logger.error : logger.warn)(
      'no FCM tokens registered for recipient; push not delivered',
      { uid, app, channelId, receiptKey },
    );
    await markReceipt(receiptKey, { status: 'sent', tokens: 0, success: 0, sentAt: FieldValue.serverTimestamp() });
    return { tokens: 0, success: 0, failure: 0 };
  }

  const tokens = tokenDocs.map((d) => d.id);
  const base = {
    notification: { title, body },
    data: stringifyData(data),
    android: {
      priority: 'high',
      notification: {
        channelId,
        priority: critical ? 'max' : 'high',
        defaultSound: true,
      },
    },
    apns: {
      headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
      payload: {
        aps: {
          sound: 'default',
          ...(critical ? { 'interruption-level': 'time-sensitive' } : {}),
        },
      },
    },
  };

  let success = 0;
  let failure = 0;
  const toPrune = [];
  let transient = false;
  try {
    for (let i = 0; i < tokens.length; i += MULTICAST_LIMIT) {
      const chunk = tokens.slice(i, i + MULTICAST_LIMIT);
      const res = await messaging().sendEachForMulticast({ ...base, tokens: chunk });
      success += res.successCount;
      failure += res.failureCount;
      const c = classifySendErrors(chunk, res.responses);
      toPrune.push(...c.prune);
      transient = transient || c.transient;
      for (const e of c.otherErrors) {
        logger.error('FCM send error', { uid, code: e.code, message: e.message, receiptKey });
      }
    }
  } catch (err) {
    // Whole-request failure (network/auth): release so the retry resends.
    await releaseReceipt(receiptKey);
    throw err;
  }

  if (toPrune.length) {
    const batch = db().batch();
    for (const t of toPrune) batch.delete(db().collection(COLLECTIONS.FCM_TOKENS).doc(t));
    await batch.commit().catch((err) =>
      logger.warn('failed to prune stale FCM tokens', { uid, error: err.message }));
    logger.info('pruned stale FCM tokens', { uid, count: toPrune.length });
  }

  if (success === 0 && transient) {
    await releaseReceipt(receiptKey);
    throw new Error(`transient FCM failure for ${receiptKey}; will retry`);
  }
  await markReceipt(receiptKey, {
    status: 'sent', tokens: tokens.length, success, failure,
    sentAt: FieldValue.serverTimestamp(),
  });
  if (success === 0) {
    (critical ? logger.error : logger.warn)('push delivered to no device', { uid, channelId, receiptKey });
  }
  return { tokens: tokens.length, success, failure };
}

module.exports = { sendPushToUser, stringifyData };
