'use strict';

/**
 * Constants shared by functions, scripts and tests. Values mirror
 * docs/DATA_MODEL.md (the binding contract) — change both together.
 */

const REGION = 'us-central1';

const ROLES = Object.freeze({
  PATIENT: 'patient',
  THERAPIST_PENDING: 'therapist_pending',
  THERAPIST: 'therapist',
});

const COLLECTIONS = Object.freeze({
  USERS: 'users',
  INVITE_CODES: 'invite_codes',
  FCM_TOKENS: 'fcm_tokens',
  VITALS: 'vitals',
  DAILY_LOGS: 'daily_logs',
  ASSESSMENTS: 'clinical_assessments',
  CRISIS_EVENTS: 'crisis_events',
  CHATS: 'chats',
  MESSAGES: 'messages',
  APPOINTMENTS: 'appointments',
  JOURNAL_ENTRIES: 'journal_entries',
  REMINDERS: 'reminders',
  // Server-only bookkeeping (no client access; default-deny in rules).
  ALERT_COOLDOWNS: 'alert_cooldowns',
  PUSH_RECEIPTS: 'push_receipts',
});

const CHANNELS = Object.freeze({
  CLINICAL_CRITICAL: 'clinical_critical',
  CHAT_MESSAGES: 'chat_messages',
  APPOINTMENTS: 'appointments',
});

const PUSH_TYPES = Object.freeze({
  CRISIS: 'crisis',
  CHAT: 'chat',
  APPOINTMENT: 'appointment',
});

const SEVERITY_RANK = Object.freeze({ medium: 1, high: 2, critical: 3 });

// Invite code alphabet: no 0/O, 1/I/L — unambiguous when read aloud or typed.
const INVITE_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const INVITE_CODE_LENGTH = 8;

const VITAL_ALERT_COOLDOWN_MS = 30 * 60 * 1000;

module.exports = {
  REGION,
  ROLES,
  COLLECTIONS,
  CHANNELS,
  PUSH_TYPES,
  SEVERITY_RANK,
  INVITE_CODE_ALPHABET,
  INVITE_CODE_LENGTH,
  VITAL_ALERT_COOLDOWN_MS,
};
