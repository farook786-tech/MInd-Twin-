'use strict';

/**
 * Cloud Functions (Blaze) wrappers for the notification triggers. Logic lives
 * in ../core/triggers.js and is shared with the backend runner (Spark plan).
 */

const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { COLLECTIONS } = require('../logic/constants');
const { core } = require('../runtime');
const { eventCtx } = require('./eventContext');

const TRIGGER_OPTS = { retry: true };

/** crisis_events/{eventId} created: high-priority push to the therapist. */
const onCrisisEventCreated = onDocumentCreated(
  { document: `${COLLECTIONS.CRISIS_EVENTS}/{eventId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    await core().triggers.crisisEventCreated(event.data, eventCtx(event));
  });

/** chats/{chatId}/messages/{messageId} created: push to receiverId. */
const onMessageCreated = onDocumentCreated(
  { document: `${COLLECTIONS.CHATS}/{chatId}/${COLLECTIONS.MESSAGES}/{messageId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    await core().triggers.messageCreated(event.data, eventCtx(event));
  });

/** appointments/{appointmentId} written: meeting link + push other party. */
const onAppointmentWritten = onDocumentWritten(
  { document: `${COLLECTIONS.APPOINTMENTS}/{appointmentId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    await core().triggers.appointmentWritten(event.data, eventCtx(event));
  });

module.exports = { onCrisisEventCreated, onMessageCreated, onAppointmentWritten };
