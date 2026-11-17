'use strict';

const { toMillis } = require('./vitals');

/**
 * Pure planning for onAppointmentWritten.
 * @param {object|null} before
 * @param {object|null} after
 * @return {{setMeetingUrl: boolean, recipients: Array<'patient'|'therapist'>,
 *   title: string|null, body: string|null}}
 */
function planAppointmentEffects(before, after) {
  const none = { setMeetingUrl: false, recipients: [], title: null, body: null };
  if (!after) return none;

  const setMeetingUrl = after.status === 'scheduled' &&
    after.isVirtual === true &&
    !(typeof after.meetingUrl === 'string' && after.meetingUrl.length > 0);

  let recipients = [];
  let title = null;
  let body = null;
  const therapistName = after.therapistName || 'your therapist';
  const patientName = after.patientName || 'A patient';

  if (!before) {
    if (after.status === 'requested') {
      recipients = ['therapist'];
      title = 'New appointment request';
      body = `${patientName} requested an appointment.`;
    } else if (after.status === 'scheduled') {
      recipients = ['patient'];
      title = 'Appointment scheduled';
      body = `${therapistName} scheduled an appointment with you.`;
    }
    return { setMeetingUrl, recipients, title, body };
  }

  const statusChanged = before.status !== after.status;
  const scheduledChanged = toMillis(before.scheduledAt) !== toMillis(after.scheduledAt);

  if (statusChanged) {
    switch (after.status) {
      case 'scheduled':
        recipients = ['patient'];
        title = 'Appointment confirmed';
        body = `${therapistName} confirmed your appointment.`;
        break;
      case 'declined':
        recipients = ['patient'];
        title = 'Appointment request declined';
        body = `${therapistName} could not accept your request. Please propose another time.`;
        break;
      case 'cancelled':
        if (after.cancelledBy && after.cancelledBy === after.patientId) {
          recipients = ['therapist'];
          body = `${patientName} cancelled an appointment.`;
        } else if (after.cancelledBy && after.cancelledBy === after.therapistId) {
          recipients = ['patient'];
          body = `${therapistName} cancelled your appointment.`;
        } else {
          recipients = ['patient', 'therapist'];
          body = 'An appointment was cancelled.';
        }
        title = 'Appointment cancelled';
        break;
      case 'completed':
      case 'no_show':
        // Bookkeeping by the therapist; no push needed.
        break;
      case 'requested':
        recipients = ['therapist'];
        title = 'Appointment request';
        body = `${patientName} requested an appointment.`;
        break;
      default:
        break;
    }
  } else if (scheduledChanged && after.status === 'scheduled') {
    recipients = ['patient'];
    title = 'Appointment rescheduled';
    body = `${therapistName} changed the time of your appointment.`;
  }
  return { setMeetingUrl, recipients, title, body };
}

const MAX_DURATION_MIN = 60;

/** True when an appointment just became scheduled or was moved in time. */
function needsConflictCheck(before, after) {
  if (!after || after.status !== 'scheduled' || toMillis(after.scheduledAt) === null) return false;
  if (!before || before.status !== 'scheduled') return true;
  return toMillis(before.scheduledAt) !== toMillis(after.scheduledAt) ||
    before.durationMinutes !== after.durationMinutes;
}

function durationMs(d) {
  const m = typeof d === 'number' && d > 0 && d <= 24 * 60 ? d : MAX_DURATION_MIN;
  return m * 60 * 1000;
}

/**
 * Half-open interval overlap [start, end) against the therapist's other
 * scheduled appointments (back-to-back is not a conflict).
 * @param {string} selfId
 * @param {{scheduledAt: unknown, durationMinutes: number}} target
 * @param {Array<{id: string, scheduledAt: unknown, durationMinutes: number}>} others
 * @return {string[]} ids of overlapping appointments
 */
function findOverlaps(selfId, target, others) {
  const start = toMillis(target.scheduledAt);
  if (start === null) return [];
  const end = start + durationMs(target.durationMinutes);
  return others
    .filter((o) => o.id !== selfId)
    .filter((o) => {
      const oStart = toMillis(o.scheduledAt);
      if (oStart === null) return false;
      const oEnd = oStart + durationMs(o.durationMinutes);
      return start < oEnd && oStart < end;
    })
    .map((o) => o.id)
    .sort();
}

module.exports = {
  MAX_DURATION_MIN,
  planAppointmentEffects,
  needsConflictCheck,
  findOverlaps,
};
