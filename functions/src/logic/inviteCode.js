'use strict';

const crypto = require('node:crypto');
const { INVITE_CODE_ALPHABET, INVITE_CODE_LENGTH } = require('./constants');

const INVITE_CODE_PATTERN = new RegExp(
  `^[${INVITE_CODE_ALPHABET}]{${INVITE_CODE_LENGTH}}$`,
);

/**
 * Generates a crypto-random invite code. crypto.randomInt uses rejection
 * sampling, so every alphabet character is equally likely (no modulo bias).
 * @param {(max: number) => number} [randomInt] injectable for tests
 * @return {string}
 */
function generateInviteCode(randomInt = (max) => crypto.randomInt(max)) {
  let code = '';
  for (let i = 0; i < INVITE_CODE_LENGTH; i += 1) {
    code += INVITE_CODE_ALPHABET[randomInt(INVITE_CODE_ALPHABET.length)];
  }
  return code;
}

/**
 * Normalises user input (trim, uppercase, strip spaces/dashes). Returns null
 * if the result is not a syntactically valid code.
 * @param {unknown} raw
 * @return {string|null}
 */
function normalizeInviteCode(raw) {
  if (typeof raw !== 'string' || raw.length > 32) return null;
  const code = raw.trim().toUpperCase().replace(/[\s-]/g, '');
  return INVITE_CODE_PATTERN.test(code) ? code : null;
}

/**
 * Crypto-random suffix for meeting rooms (lowercase alnum, unguessable).
 * @param {number} length
 * @return {string}
 */
function randomToken(length) {
  const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
  let out = '';
  for (let i = 0; i < length; i += 1) {
    out += alphabet[crypto.randomInt(alphabet.length)];
  }
  return out;
}

/**
 * Jitsi room URL: https://meet.jit.si/MindTwin-<id>-<10 random chars>.
 * The appointment id is sanitised to URL-safe characters.
 * @param {string} appointmentId
 * @param {string} [suffix] injectable for tests
 * @return {string}
 */
function buildMeetingUrl(appointmentId, suffix = randomToken(10)) {
  const safeId = String(appointmentId).replace(/[^A-Za-z0-9_-]/g, '');
  return `https://meet.jit.si/MindTwin-${safeId}-${suffix}`;
}

module.exports = {
  INVITE_CODE_PATTERN,
  generateInviteCode,
  normalizeInviteCode,
  randomToken,
  buildMeetingUrl,
};
