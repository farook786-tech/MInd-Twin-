'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const v = require('../../src/logic/vitals');

const NOW = Date.UTC(2026, 10, 17, 12, 0, 0);
const ts = (ms) => ({ toMillis: () => ms });
const doc = (over) => ({
  patientId: 'p1', therapistId: 't1', type: 'heart_rate', value: 80, unit: 'bpm',
  measuredAt: ts(NOW), source: 'wear_os', ...over,
});

test('defaults used when no override', () => {
  const { thresholds, warnings } = v.resolveThresholds(undefined);
  assert.deepEqual(thresholds, { heartRateHigh: 120, heartRateLow: 45, sleepHoursLow: 4 });
  assert.equal(warnings.length, 0);
});

test('valid per-patient override applied field by field', () => {
  const { thresholds } = v.resolveThresholds({ heartRateHigh: 100 });
  assert.deepEqual(thresholds, { heartRateHigh: 100, heartRateLow: 45, sleepHoursLow: 4 });
});

test('out-of-bounds / wrong-type override falls back to defaults (fail safe)', () => {
  const r = v.resolveThresholds({ heartRateHigh: 1200, heartRateLow: '50', sleepHoursLow: -1 });
  assert.deepEqual(r.thresholds, v.DEFAULT_THRESHOLDS);
  assert.equal(r.warnings.length, 3);
  assert.deepEqual(v.resolveThresholds('junk').thresholds, v.DEFAULT_THRESHOLDS);
});

test('inverted heart-rate override reverts both HR thresholds', () => {
  const r = v.resolveThresholds({ heartRateHigh: 80, heartRateLow: 80 });
  assert.equal(r.thresholds.heartRateHigh, 120);
  assert.equal(r.thresholds.heartRateLow, 45);
  assert.match(r.warnings.join(), /heartRateLow >= heartRateHigh/);
});

test('threshold bounds match the rules (HR high 80-220, low 25-80, sleep 0-12)', () => {
  const ok = v.resolveThresholds({ heartRateHigh: 220, heartRateLow: 25, sleepHoursLow: 12 });
  assert.equal(ok.warnings.length, 0);
  for (const bad of [{ heartRateHigh: 79 }, { heartRateHigh: 221 }, { heartRateLow: 24 },
    { heartRateLow: 81 }, { sleepHoursLow: 12.5 }, { sleepHoursLow: -0.1 }]) {
    assert.equal(v.resolveThresholds(bad).warnings.length, 1, JSON.stringify(bad));
  }
});

test('non-physical heart rates are sensor errors, never alerts', () => {
  for (const value of [0, -5, 301, 1000]) {
    const r = v.validateVitalReading(doc({ value }));
    assert.equal(r.ok, false);
    assert.equal(r.sensorError, true, `value ${value}`);
  }
  assert.equal(v.validateVitalReading(doc({ value: 300 })).ok, true);
  assert.equal(v.validateVitalReading(doc({ value: NaN })).sensorError, true);
});

test('sleep / steps sanity bounds', () => {
  assert.equal(v.validateVitalReading(doc({ type: 'sleep', unit: 'hours', value: 25 })).sensorError, true);
  assert.equal(v.validateVitalReading(doc({ type: 'sleep', unit: 'hours', value: 0 })).ok, true);
  assert.equal(v.validateVitalReading(doc({ type: 'steps', unit: 'count', value: -1 })).sensorError, true);
});

test('malformed docs rejected (not sensor errors)', () => {
  assert.equal(v.validateVitalReading(doc({ unit: 'hours' })).ok, false);
  assert.equal(v.validateVitalReading(doc({ type: 'spo2' })).ok, false);
  assert.equal(v.validateVitalReading(doc({ patientId: '' })).ok, false);
  assert.equal(v.validateVitalReading(doc({ measuredAt: 'yesterday' })).ok, false);
  assert.equal(v.validateVitalReading(null).ok, false);
});

test('heart-rate thresholds and severity', () => {
  const t = v.DEFAULT_THRESHOLDS;
  const ev = (value) => v.evaluateVital({ type: 'heart_rate', value, unit: 'bpm' }, t);
  assert.equal(ev(120), null, 'exactly at high threshold is not an alert');
  assert.equal(ev(45), null, 'exactly at low threshold is not an alert');
  assert.equal(ev(80), null);
  assert.deepEqual(ev(121), { eventType: 'vital_high', severity: 'high', threshold: 120, direction: 'high' });
  assert.equal(ev(150).severity, 'critical');
  assert.deepEqual(ev(44), { eventType: 'vital_low', severity: 'high', threshold: 45, direction: 'low' });
  assert.equal(ev(40).severity, 'critical');
});

test('sleep below 4 h alerts (medium); steps never alert', () => {
  const t = v.DEFAULT_THRESHOLDS;
  assert.equal(v.evaluateVital({ type: 'sleep', value: 4, unit: 'hours' }, t), null);
  const r = v.evaluateVital({ type: 'sleep', value: 3.5, unit: 'hours' }, t);
  assert.equal(r.eventType, 'vital_low');
  assert.equal(r.severity, 'medium');
  assert.equal(v.evaluateVital({ type: 'steps', value: 0, unit: 'count' }, t), null);
});

test('custom thresholds respected', () => {
  const { thresholds } = v.resolveThresholds({ heartRateHigh: 100 });
  assert.equal(v.evaluateVital({ type: 'heart_rate', value: 105, unit: 'bpm' }, thresholds).eventType, 'vital_high');
});

test('30-minute cooldown', () => {
  const min = 60 * 1000;
  assert.equal(v.isInCooldown(null, NOW), false);
  assert.equal(v.isInCooldown(NOW - 29 * min, NOW), true);
  assert.equal(v.isInCooldown(NOW - 30 * min, NOW), false);
  assert.equal(v.isInCooldown(NOW + 5 * min, NOW), false, 'future stamp (clock skew) does not suppress');
  assert.notEqual(v.cooldownField('heart_rate', 'vital_high'), v.cooldownField('heart_rate', 'vital_low'));
});

test('latestVitals only moves forward', () => {
  assert.equal(v.isNewerReading(null, NOW), true);
  assert.equal(v.isNewerReading(NOW, NOW - 1), false);
  assert.equal(v.isNewerReading(NOW, NOW), false);
  assert.equal(v.isNewerReading(NOW - 1, NOW), true);
});

test('deterministic crisis id per vital doc', () => {
  assert.equal(v.crisisIdForVital('p1_heart_rate_123'), 'vital_p1_heart_rate_123');
});

test('alert text includes value and threshold', () => {
  const reading = { type: 'heart_rate', value: 130, unit: 'bpm', measuredAtMillis: NOW };
  const { title, message } = v.describeVitalAlert('Ana', reading,
    { direction: 'high', threshold: 120 });
  assert.match(title, /Heart rate high: Ana/);
  assert.match(message, /130 bpm/);
  assert.match(message, /120 bpm/);
});

test('vitalDocKind: window / immediate / single', () => {
  const win = doc({ value: 72, min: 60, max: 130, sampleCount: 5, windowStart: ts(NOW - 300000) });
  assert.equal(v.vitalDocKind(win), 'window');
  assert.equal(v.vitalDocKind(doc({ value: 131, immediate: true })), 'immediate');
  assert.equal(v.vitalDocKind(doc()), 'single');
  assert.equal(v.vitalDocKind(doc({ type: 'sleep', unit: 'hours', value: 6 })), 'single');
  assert.equal(v.vitalDocKind(null), 'single');
});

test('aggregate windows are skipped by the trigger; immediates and singles are evaluated', () => {
  const win = doc({ value: 72, min: 60, max: 130, sampleCount: 5, windowStart: ts(NOW - 300000) });
  assert.equal(v.skipVitalTrigger(win), true);
  assert.equal(v.skipVitalTrigger(doc({ value: 131, immediate: true })), false);
  assert.equal(v.skipVitalTrigger(doc({ value: 131 })), false);
  // The immediate doc still validates and alerts exactly like a legacy single reading.
  const imm = v.validateVitalReading(doc({ value: 131, immediate: true }));
  assert.equal(imm.ok, true);
  assert.equal(v.evaluateVital(imm.reading, v.DEFAULT_THRESHOLDS).eventType, 'vital_high');
});

test('windowBreach reports min/max breaches of an aggregate (reporting only)', () => {
  const t = v.DEFAULT_THRESHOLDS;
  const w = (min, max) => doc({ value: 80, min, max, sampleCount: 5, windowStart: ts(NOW - 300000) });
  assert.equal(v.windowBreach(w(60, 130), t), 'high');
  assert.equal(v.windowBreach(w(40, 90), t), 'low');
  assert.equal(v.windowBreach(w(60, 120), t), null); // boundary is not a breach (strict >, <)
  assert.equal(v.windowBreach(doc({ value: 200 }), t), null); // not a window
});
