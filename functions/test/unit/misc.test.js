'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const ic = require('../../src/logic/inviteCode');
const { INVITE_CODE_ALPHABET } = require('../../src/logic/constants');
const { planAppointmentEffects, needsConflictCheck, findOverlaps } = require('../../src/logic/appointments');
const { classifySendErrors } = require('../../src/logic/pushErrors');
const val = require('../../src/logic/validation');

const ts = (ms) => ({ toMillis: () => ms });

test('invite codes: 8 chars from the unambiguous alphabet', () => {
  for (let i = 0; i < 500; i += 1) {
    const code = ic.generateInviteCode();
    assert.match(code, ic.INVITE_CODE_PATTERN);
  }
  for (const ch of '01ILO') assert.equal(INVITE_CODE_ALPHABET.includes(ch), false);
});

test('invite codes are random (no repeats in 2000 draws)', () => {
  const seen = new Set();
  for (let i = 0; i < 2000; i += 1) seen.add(ic.generateInviteCode());
  assert.equal(seen.size, 2000);
});

test('invite code normalisation', () => {
  assert.equal(ic.normalizeInviteCode(' abcd-2345 '), 'ABCD2345');
  assert.equal(ic.normalizeInviteCode('ABCD234O'), null, 'O not in alphabet');
  assert.equal(ic.normalizeInviteCode('ABC'), null);
  assert.equal(ic.normalizeInviteCode(12345678), null);
  assert.equal(ic.normalizeInviteCode('A'.repeat(100)), null);
});

test('meeting url format', () => {
  assert.equal(ic.buildMeetingUrl('apt1', 'abcdefghij'), 'https://meet.jit.si/MindTwin-apt1-abcdefghij');
  assert.match(ic.buildMeetingUrl('x/../y'), /^https:\/\/meet\.jit\.si\/MindTwin-xy-[a-z2-9]{10}$/);
  assert.notEqual(ic.buildMeetingUrl('a'), ic.buildMeetingUrl('a'));
});

const appt = (over) => ({
  patientId: 'p', therapistId: 't', patientName: 'Pat', therapistName: 'Dr T',
  status: 'requested', isVirtual: true, meetingUrl: null, scheduledAt: null, ...over,
});

test('appointment: patient request notifies therapist, no meeting url', () => {
  const p = planAppointmentEffects(null, appt());
  assert.deepEqual(p.recipients, ['therapist']);
  assert.equal(p.setMeetingUrl, false);
});

test('appointment: scheduled + virtual sets url once, notifies patient', () => {
  const p = planAppointmentEffects(appt(), appt({ status: 'scheduled', scheduledAt: ts(1) }));
  assert.equal(p.setMeetingUrl, true);
  assert.deepEqual(p.recipients, ['patient']);
  const again = planAppointmentEffects(
    appt({ status: 'scheduled', scheduledAt: ts(1) }),
    appt({ status: 'scheduled', scheduledAt: ts(1), meetingUrl: 'https://meet.jit.si/x' }));
  assert.equal(again.setMeetingUrl, false, 'never overwritten');
  assert.deepEqual(again.recipients, [], 'function own write does not re-notify');
});

test('appointment: in-person never gets a url', () => {
  assert.equal(planAppointmentEffects(null, appt({ status: 'scheduled', isVirtual: false })).setMeetingUrl, false);
});

test('appointment: cancellation notifies the other party', () => {
  const before = appt({ status: 'scheduled' });
  assert.deepEqual(planAppointmentEffects(before, appt({ status: 'cancelled', cancelledBy: 'p' })).recipients, ['therapist']);
  assert.deepEqual(planAppointmentEffects(before, appt({ status: 'cancelled', cancelledBy: 't' })).recipients, ['patient']);
  assert.deepEqual(planAppointmentEffects(before, appt({ status: 'cancelled' })).recipients, ['patient', 'therapist']);
});

test('appointment: reschedule notifies patient; completed does not', () => {
  const before = appt({ status: 'scheduled', scheduledAt: ts(1) });
  assert.deepEqual(planAppointmentEffects(before, appt({ status: 'scheduled', scheduledAt: ts(2) })).recipients, ['patient']);
  assert.deepEqual(planAppointmentEffects(before, appt({ status: 'completed', scheduledAt: ts(1) })).recipients, []);
  assert.deepEqual(planAppointmentEffects(before, null).recipients, []);
});

test('double booking detection', () => {
  const H = 3600 * 1000;
  const target = { scheduledAt: ts(10 * H), durationMinutes: 60 };
  const others = [
    { id: 'self', scheduledAt: ts(10 * H), durationMinutes: 60 },
    { id: 'overlap', scheduledAt: ts(10.5 * H), durationMinutes: 30 },
    { id: 'backToBack', scheduledAt: ts(11 * H), durationMinutes: 30 },
    { id: 'before', scheduledAt: ts(9 * H), durationMinutes: 60 },
    { id: 'earlierOverlap', scheduledAt: ts(9.5 * H), durationMinutes: 45 },
  ];
  assert.deepEqual(findOverlaps('self', target, others), ['earlierOverlap', 'overlap']);
  assert.equal(needsConflictCheck(appt(), appt({ status: 'scheduled', scheduledAt: ts(1) })), true);
  assert.equal(needsConflictCheck(appt({ status: 'scheduled', scheduledAt: ts(1) }),
    appt({ status: 'scheduled', scheduledAt: ts(1), conflict: true })), false, 'own flag write does not loop');
});

test('FCM error classification', () => {
  const tokens = ['a', 'b', 'c', 'd'];
  const r = classifySendErrors(tokens, [
    { success: true },
    { success: false, error: { code: 'messaging/registration-token-not-registered' } },
    { success: false, error: { code: 'messaging/invalid-argument' } },
    { success: false, error: { code: 'messaging/internal-error' } },
  ]);
  assert.deepEqual(r.prune, ['b', 'c']);
  assert.equal(r.transient, true);
  // invalid-argument with no success at all => likely payload bug: do NOT prune
  const r2 = classifySendErrors(['x'], [{ success: false, error: { code: 'messaging/invalid-argument' } }]);
  assert.deepEqual(r2.prune, []);
  assert.equal(r2.otherErrors.length, 1);
});

test('input validation', () => {
  assert.equal(val.validateName('  Ana   Silva '), 'Ana Silva');
  assert.throws(() => val.validateName(''), /name/);
  assert.throws(() => val.validateName('x'.repeat(101)), /name/);
  assert.throws(() => val.validateName('a\u0000b'), /invalid/);
  assert.throws(() => val.validateName(42), /name/);
  assert.equal(val.validateOptionalText(undefined, 'x', 5), null);
  assert.throws(() => val.validateOptionalText('toolong', 'x', 5), /at most/);
  assert.throws(() => val.validateUid('../etc', 'u'), /valid user id/);
  assert.throws(() => val.requireObject([1]), /object/);
});
