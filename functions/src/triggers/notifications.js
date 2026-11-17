'use strict';

const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions/v2');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { db } = require('../admin');
const { COLLECTIONS, CHANNELS, PUSH_TYPES } = require('../logic/constants');
const { buildMeetingUrl } = require('../logic/inviteCode');
const { toMillis } = require('../logic/vitals');
const {
  planAppointmentEffects, needsConflictCheck, findOverlaps, MAX_DURATION_MIN,
} = require('../logic/appointments');
const { sendPushToUser } = require('../push');

const TRIGGER_OPTS = { retry: true };
// Chat / appointment pushes older than this are dropped instead of retried
// (a stale "new message" push hours later is noise). Crisis pushes never expire.
const MAX_NON_CRITICAL_AGE_MS = 6 * 60 * 60 * 1000;

function isTooOld(event, maxAgeMs) {
  const t = Date.parse(event.time);
  return Number.isFinite(t) && Date.now() - t > maxAgeMs;
}

const DEFAULT_CRISIS_TITLES = {
  sos: 'SOS',
  checkin_crisis: 'Check-in crisis',
  chat_crisis: 'Crisis language in chat',
  high_risk: 'High risk',
  phq9_severe: 'PHQ-9 alert',
  vital_high: 'Vital sign high',
  vital_low: 'Vital sign low',
};

function truncate(s, n) {
  const str = String(s || '');
  return str.length > n ? `${str.slice(0, n - 1)}…` : str;
}

/** crisis_events/{eventId} created: high-priority push to the therapist. */
const onCrisisEventCreated = onDocumentCreated(
  { document: `${COLLECTIONS.CRISIS_EVENTS}/{eventId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    const eventId = event.params.eventId;
    const c = event.data.data();
    const patientId = c.patientId;
    if (typeof patientId !== 'string' || !patientId) {
      logger.error('crisis event without patientId', { eventId });
      return;
    }
    // Prefer the patient's CURRENT therapist (authoritative) over the stamp.
    const userSnap = await db().collection(COLLECTIONS.USERS).doc(patientId).get();
    const therapistId = (userSnap.exists && userSnap.get('therapistId')) || c.therapistId;
    if (!therapistId) {
      logger.error('CRISIS EVENT HAS NO THERAPIST — push not sent', { eventId, patientId });
      return;
    }
    const patientName = c.patientName || (userSnap.exists && userSnap.get('name')) || 'Patient';
    const prefix = c.severity === 'critical' ? 'URGENT: ' : '';
    const title = truncate(c.title || `${prefix}${DEFAULT_CRISIS_TITLES[c.eventType] || 'Alert'}: ${patientName}`, 120);
    const body = truncate(c.message || `${patientName} needs attention. Open MindTwin now.`, 240);
    const result = await sendPushToUser({
      uid: therapistId,
      app: 'therapist',
      channelId: CHANNELS.CLINICAL_CRITICAL,
      title,
      body,
      data: { type: PUSH_TYPES.CRISIS, eventId, patientId },
      receiptKey: `crisis_${eventId}`,
    });
    logger.info('crisis push', { eventId, therapistId, ...result });
  });

/** chats/{chatId}/messages/{messageId} created: push to receiverId. */
const onMessageCreated = onDocumentCreated(
  { document: `${COLLECTIONS.CHATS}/{chatId}/${COLLECTIONS.MESSAGES}/{messageId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    const { chatId, messageId } = event.params;
    if (isTooOld(event, MAX_NON_CRITICAL_AGE_MS)) {
      logger.warn('dropping stale chat push', { chatId, messageId });
      return;
    }
    const m = event.data.data();
    const participants = String(chatId).split('__');
    if (participants.length !== 2 ||
        !participants.includes(m.senderId) ||
        !participants.includes(m.receiverId) ||
        m.senderId === m.receiverId) {
      logger.error('message sender/receiver do not match chat id', { chatId, messageId });
      return;
    }
    // Privacy: message text is NOT put in the push (lock screens are visible
    // to others; this is mental-health content).
    const senderName = truncate(m.senderName || 'MindTwin', 60);
    await sendPushToUser({
      uid: m.receiverId,
      app: null,
      channelId: CHANNELS.CHAT_MESSAGES,
      title: `New message from ${senderName}`,
      body: 'Open MindTwin to read it.',
      data: { type: PUSH_TYPES.CHAT, chatId, senderId: m.senderId, senderName },
      receiptKey: `msg_${chatId}_${messageId}`,
    });
  });

/**
 * Server-side double-booking guard: clients check overlaps too, but two
 * concurrent writes can race. Flags `conflict` / `conflictWith` on the
 * appointment (server-only fields) and alerts the therapist once.
 */
async function checkDoubleBooking(event, appointmentId, after) {
  const start = toMillis(after.scheduledAt);
  const windowStart = Timestamp.fromMillis(start - MAX_DURATION_MIN * 60 * 1000);
  const windowEnd = Timestamp.fromMillis(start + 24 * 60 * 60 * 1000);
  const snap = await db().collection(COLLECTIONS.APPOINTMENTS)
    .where('therapistId', '==', after.therapistId)
    .where('status', '==', 'scheduled')
    .where('scheduledAt', '>=', windowStart)
    .where('scheduledAt', '<', windowEnd)
    .get();
  const others = snap.docs.map((d) => ({
    id: d.id, scheduledAt: d.get('scheduledAt'), durationMinutes: d.get('durationMinutes'),
  }));
  const overlaps = findOverlaps(appointmentId, after, others);
  const conflict = overlaps.length > 0;
  const prevIds = Array.isArray(after.conflictWith) ? [...after.conflictWith].sort() : [];
  if (after.conflict !== conflict || prevIds.join(',') !== overlaps.join(',')) {
    await db().collection(COLLECTIONS.APPOINTMENTS).doc(appointmentId)
      .update({ conflict, conflictWith: overlaps });
  }
  if (conflict) {
    logger.warn('appointment double booking detected', { appointmentId, overlaps });
    await sendPushToUser({
      uid: after.therapistId,
      app: 'therapist',
      channelId: CHANNELS.APPOINTMENTS,
      title: 'Possible double booking',
      body: 'An appointment overlaps another scheduled appointment. Please review.',
      data: { type: PUSH_TYPES.APPOINTMENT, appointmentId },
      receiptKey: `apptconflict_${event.id}`,
    });
  }
}

/** appointments/{appointmentId} written: meeting link + push other party. */
const onAppointmentWritten = onDocumentWritten(
  { document: `${COLLECTIONS.APPOINTMENTS}/{appointmentId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    const appointmentId = event.params.appointmentId;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    const plan = planAppointmentEffects(before, after);

    if (plan.setMeetingUrl) {
      const ref = db().collection(COLLECTIONS.APPOINTMENTS).doc(appointmentId);
      await db().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) return;
        const d = snap.data();
        // Only set once; never overwrite an existing link.
        if (d.status !== 'scheduled' || d.isVirtual !== true || d.meetingUrl) return;
        tx.update(ref, {
          meetingUrl: buildMeetingUrl(appointmentId),
          meetingUrlCreatedAt: FieldValue.serverTimestamp(),
        });
      });
    }

    if (needsConflictCheck(before, after)) {
      await checkDoubleBooking(event, appointmentId, after);
    }

    if (!plan.recipients.length) return;
    if (isTooOld(event, MAX_NON_CRITICAL_AGE_MS)) {
      logger.warn('dropping stale appointment push', { appointmentId });
      return;
    }
    for (const who of plan.recipients) {
      const uid = who === 'patient' ? after.patientId : after.therapistId;
      if (!uid) continue;
      await sendPushToUser({
        uid,
        app: who,
        channelId: CHANNELS.APPOINTMENTS,
        title: plan.title,
        body: plan.body,
        data: { type: PUSH_TYPES.APPOINTMENT, appointmentId },
        receiptKey: `appt_${event.id}_${who}`,
      });
    }
  });

module.exports = { onCrisisEventCreated, onMessageCreated, onAppointmentWritten };
