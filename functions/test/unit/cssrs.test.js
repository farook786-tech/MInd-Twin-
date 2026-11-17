'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const cssrs = require('../../src/logic/cssrs');
const clinical = require('../../src/logic/clinical');

// Shape written by lib/screens/patient/cssrs_screener_screen.dart
const answers = (over = {}) => ({
  q1: false, q2: false, q3: null, q4: null, q5: null, q6: false, q6Recent: null, ...over,
});
const doc = (over = {}, risk) => {
  const a = answers(over);
  return {
    patientId: 'p1', therapistId: 't1', type: 'cssrs', cssrsAnswers: a,
    cssrsRisk: risk || cssrs.triageCssrs(a).risk, timestamp: 1, clientCreatedAt: 1,
  };
};

test('triage table (Columbia Screen Version - Recent)', () => {
  const cases = [
    [{}, 'none'],
    [{ q1: true }, 'low'],
    [{ q1: true, q2: true, q3: false, q4: false, q5: false }, 'low'],
    [{ q2: true, q3: true, q4: false, q5: false }, 'moderate'],
    [{ q6: true, q6Recent: false }, 'moderate'],
    [{ q2: true, q3: false, q4: true, q5: false }, 'high'],
    [{ q2: true, q3: true, q4: false, q5: true }, 'high'],
    [{ q6: true, q6Recent: true }, 'high'],
    [{ q6: true }, 'high'], // unknown recency fails safe
    [{ q2: true, q3: true, q4: true, q5: false, q6: true, q6Recent: false }, 'high'],
  ];
  for (const [over, expected] of cases) {
    assert.equal(cssrs.triageCssrs(answers(over)).risk, expected, JSON.stringify(over));
  }
});

test('positive items are listed for explainability', () => {
  const t = cssrs.triageCssrs(answers({ q1: true, q2: true, q3: true, q4: true, q5: false, q6: true, q6Recent: false }));
  assert.deepEqual(t.positiveItems, ['q1', 'q2', 'q3', 'q4', 'q6_lifetime']);
});

test('unusable answers => null', () => {
  assert.equal(cssrs.triageCssrs(null), null);
  assert.equal(cssrs.triageCssrs({ q1: 'yes', q2: false, q6: false }), null);
  assert.equal(cssrs.triageCssrs({ q1: true }), null);
});

test('maxRisk', () => {
  assert.equal(cssrs.maxRisk('low', 'high'), 'high');
  assert.equal(cssrs.maxRisk('moderate', 'none'), 'moderate');
  assert.equal(cssrs.maxRisk(null, 'low'), 'low');
  assert.equal(cssrs.maxRisk('bogus', null), null);
});

test('assessment: HIGH => cssrs_high critical with item reasons', () => {
  const r = clinical.evaluateAssessment(doc({ q1: true, q2: true, q3: false, q4: true, q5: false }));
  assert.equal(r.eventType, 'cssrs_high');
  assert.equal(r.severity, 'critical');
  assert.equal(r.cssrsRisk, 'high');
  assert.ok(r.reasons.some((x) => x.includes('Q4 = yes (intent)')));
});

test('assessment: MODERATE => cssrs_moderate medium', () => {
  const r = clinical.evaluateAssessment(doc({ q6: true, q6Recent: false }));
  assert.equal(r.eventType, 'cssrs_moderate');
  assert.equal(r.severity, 'medium');
});

test('assessment: LOW / NONE => no crisis event', () => {
  assert.equal(clinical.evaluateAssessment(doc({ q1: true })), null);
  assert.equal(clinical.evaluateAssessment(doc({})), null);
});

test('stored risk more severe than recomputed wins (fail safe); unreadable answers use stored', () => {
  assert.equal(clinical.evaluateAssessment(doc({ q1: true }, 'high')).eventType, 'cssrs_high');
  const r = clinical.evaluateAssessment({ type: 'cssrs', cssrsAnswers: 'garbage', cssrsRisk: 'moderate' });
  assert.equal(r.eventType, 'cssrs_moderate');
  assert.ok(r.reasons.some((x) => x.includes('unreadable')));
});

test('cssrs docs never trigger PHQ-9 logic', () => {
  assert.equal(clinical.evaluateAssessment({ ...doc({}), totalScore: 25, item9: 3 }), null);
});

test('alert text and crisis id', () => {
  const ev = clinical.evaluateAssessment(doc({ q2: true, q3: false, q4: false, q5: true }));
  const { title, message } = clinical.describeClinicalAlert('Pat', 'assessment', ev);
  assert.equal(title, 'URGENT: C-SSRS high risk: Pat');
  assert.ok(message.includes('Q5 = yes (plan with intent)'));
  assert.equal(clinical.crisisIdForAssessment('A1'), 'assessment_A1');
  const mod = clinical.evaluateAssessment(doc({ q6: true, q6Recent: false }));
  assert.equal(clinical.describeClinicalAlert('Pat', 'assessment', mod).title, 'C-SSRS moderate risk: Pat');
});

test('planCrisisMerge on the patient-written cssrs_high doc: server facts, never un-acknowledged', () => {
  const existing = {
    patientId: 'p1', therapistId: 't1', eventType: 'cssrs_high', severity: 'critical',
    acknowledged: true, acknowledgedBy: 't1', timestamp: 1,
  };
  const verified = clinical.evaluateAssessment(doc({ q2: true, q3: true, q4: true, q5: false }));
  const u = clinical.planCrisisMerge(existing, verified);
  assert.equal(u['serverVerified.cssrsRisk'], 'high');
  assert.equal(u['serverVerified.eventType'], 'cssrs_high');
  assert.equal(u.severity, undefined, 'already critical');
  for (const k of Object.keys(u)) {
    assert.ok(!/^acknowledged|^timestamp|^patientId|^therapistId/.test(k), `must not touch ${k}`);
  }
  const after = { ...existing, serverVerified: {
    eventType: verified.eventType, severity: verified.severity, reasons: verified.reasons,
    totalScore: null, item9: null, riskScore: null, cssrsRisk: 'high',
  } };
  assert.equal(clinical.planCrisisMerge(after, verified), null, 'idempotent');
});
