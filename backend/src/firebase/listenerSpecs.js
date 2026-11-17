'use strict';

/**
 * The Cloud Functions triggers of functions/index.js, expressed as realtime
 * listeners for triggerRunner.js. Each query is bounded by a SERVER timestamp
 * field that the security rules force to request.time (or that the apps set
 * with FieldValue.serverTimestamp()), so a (re)subscribe reads only recent
 * docs. Docs without that field are never seen by the runner.
 *
 * | listener             | query field | kind   | core handler                         |
 * |----------------------|-------------|--------|--------------------------------------|
 * | vitals               | createdAt   | create | vitalCreated                         |
 * | daily_logs           | timestamp   | write  | dailyLogCreated / dailyLogUpdated    |
 * | clinical_assessments | timestamp   | create | assessmentCreated                    |
 * | crisis_events        | timestamp   | create | crisisEventCreated                   |
 * | messages (group)     | createdAt   | create | messageCreated                       |
 * | appointments         | updatedAt   | write  | appointmentWritten (+ shadow state)  |
 *
 * daily_logs updates (ML merge) do not touch `timestamp`; they are seen as
 * long as the log is younger than the subscription window (querySlackMs,
 * 2 h, renewed on every resubscribe). The apps merge ML results seconds after
 * creating the log.
 */

const { versionOf, tsMillis } = require('./triggerRunner');

const MESSAGE_PATH = /^chats\/([^/]+)\/messages\/([^/]+)$/;
// Server-only bookkeeping (default-deny in firestore.rules).
const APPOINTMENT_SHADOW_COLLECTION = '_runner_appointments';
const SHADOW_FIELDS = ['status', 'scheduledAt', 'durationMinutes'];

function snapLike(id, data) {
  return { id, exists: data !== null && data !== undefined, data: () => data || undefined };
}

function eventIdOf(doc) {
  return `${doc.id}_${versionOf(doc.updateTime)}`;
}

/**
 * @param {object} p
 * @param {ReturnType<import('../../../functions/src/core').createCore>} p.core
 * @param {() => FirebaseFirestore.Firestore} p.db
 * @param {object} p.FieldValue
 * @param {object} p.logger
 */
function buildListenerSpecs({ core, db, FieldValue, logger }) {
  const t = core.triggers;

  async function handleAppointment({ doc, before: cachedBefore }) {
    const version = versionOf(doc.updateTime);
    const shadowRef = db().collection(APPOINTMENT_SHADOW_COLLECTION).doc(doc.id);
    const shadowSnap = await shadowRef.get();
    const shadow = shadowSnap.exists ? shadowSnap.data() : null;
    // Cross-process / cross-restart marker: this or a newer version was
    // already handled (possibly by another backend instance).
    if (shadow && typeof shadow.version === 'string' && shadow.version >= version) {
      return { status: 'already-processed' };
    }
    let before = null;
    const isCreate = tsMillis(doc.createTime) === tsMillis(doc.updateTime);
    if (shadow && shadow.data) before = shadow.data;
    else if (!isCreate && cachedBefore) before = cachedBefore;
    else if (!isCreate) {
      logger.warn('appointment change without known previous state; treated as new', { appointmentId: doc.id });
    }
    const after = doc.data();
    const result = await t.appointmentWritten(
      { before: before ? snapLike(doc.id, before) : null, after: doc },
      { params: { appointmentId: doc.id }, eventId: eventIdOf(doc), eventTime: tsMillis(doc.updateTime) },
    );
    const data = {};
    for (const f of SHADOW_FIELDS) if (after[f] !== undefined) data[f] = after[f];
    await shadowRef.set({ version, data, processedAt: FieldValue.serverTimestamp() });
    return result;
  }

  const ctxOf = (doc, params) => ({
    params,
    eventId: eventIdOf(doc),
    eventTime: tsMillis(doc.updateTime),
  });

  return [
    {
      name: 'vitals',
      kind: 'create',
      query: (firestore, since) => firestore.collection('vitals').where('createdAt', '>=', since),
      handle: ({ doc }) => t.vitalCreated(doc, ctxOf(doc, { vitalId: doc.id })),
    },
    {
      name: 'daily_logs',
      kind: 'write',
      querySlackMs: 2 * 60 * 60 * 1000,
      query: (firestore, since) => firestore.collection('daily_logs').where('timestamp', '>=', since),
      handle: ({ doc, before }) => (before ?
        t.dailyLogUpdated({ before: snapLike(doc.id, before), after: doc }, ctxOf(doc, { logId: doc.id })) :
        // First time this process sees the log (new, or changed while the
        // runner was down): evaluate the current version. Deterministic
        // crisis id + merge make this idempotent.
        t.dailyLogCreated(doc, ctxOf(doc, { logId: doc.id }))),
    },
    {
      name: 'clinical_assessments',
      kind: 'create',
      query: (firestore, since) => firestore.collection('clinical_assessments').where('timestamp', '>=', since),
      handle: ({ doc }) => t.assessmentCreated(doc, ctxOf(doc, { assessmentId: doc.id })),
    },
    {
      name: 'crisis_events',
      kind: 'create',
      query: (firestore, since) => firestore.collection('crisis_events').where('timestamp', '>=', since),
      handle: ({ doc }) => t.crisisEventCreated(doc, ctxOf(doc, { eventId: doc.id })),
    },
    {
      name: 'chat_messages',
      kind: 'create',
      // Collection-group query: needs the single-field COLLECTION_GROUP index
      // on messages.createdAt (firestore.indexes.json fieldOverrides).
      query: (firestore, since) => firestore.collectionGroup('messages').where('createdAt', '>=', since),
      filter: (doc) => MESSAGE_PATH.test(doc.ref.path),
      handle: ({ doc }) => {
        const [, chatId, messageId] = MESSAGE_PATH.exec(doc.ref.path);
        return t.messageCreated(doc, {
          params: { chatId, messageId },
          eventId: eventIdOf(doc),
          eventTime: tsMillis(doc.createTime),
        });
      },
    },
    {
      name: 'appointments',
      kind: 'write',
      query: (firestore, since) => firestore.collection('appointments').where('updatedAt', '>=', since),
      handle: handleAppointment,
    },
  ];
}

module.exports = { buildListenerSpecs, APPOINTMENT_SHADOW_COLLECTION, MESSAGE_PATH };
