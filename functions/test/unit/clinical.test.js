'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const c = require('../../src/logic/clinical');

// Shape written by lib/screens/patient/phq9_assessment_screen.dart
const assessment = (phq9, extra = {}) => ({
  patientId: 'p1',
  therapistId: 't1',
  phq9Score: phq9.reduce((a, b) => a + b, 0),
  gad7Score: 3,
  answers: { phq9, gad7: [0, 0, 1, 1, 1, 0, 0] },
  type: 'phq9_gad7',
  ...extra,
});

test('daily log below 75 does not alert', () => {
  assert.equal(c.evaluateDailyLog({ riskScore: 74.9 }), null);
  assert.equal(c.evaluateDailyLog({}), null);
  assert.equal(c.evaluateDailyLog({ riskScore: 'abc' }), null);
});

test('daily log risk >= 75 => high_risk (critical from 90)', () => {
  assert.deepEqual(
    { ...c.evaluateDailyLog({ riskScore: 75 }), reasons: undefined },
    { eventType: 'high_risk', severity: 'high', riskScore: 75, reasons: undefined },
  );
  assert.equal(c.evaluateDailyLog({ riskScore: 92 }).severity, 'critical');
});

test('ML risk merged later is considered (max wins)', () => {
  assert.equal(c.extractRiskScore({ riskScore: 40, mlRisk: { riskScore: 80 } }), 80);
  assert.equal(c.evaluateDailyLog({ riskScore: 40, mlRisk: { riskScore: 80 } }).eventType, 'high_risk');
});

test('PHQ-9 item 9 > 0 => critical phq9_severe even with low total', () => {
  const r = c.evaluateAssessment(assessment([0, 0, 0, 0, 0, 0, 0, 0, 1]));
  assert.equal(r.eventType, 'phq9_severe');
  assert.equal(r.severity, 'critical');
  assert.equal(r.phq9Item9, 1);
});

test('PHQ-9 item 9 == 0 and total 19 => no alert', () => {
  assert.equal(c.evaluateAssessment(assessment([3, 3, 3, 3, 3, 2, 1, 1, 0])), null);
});

test('PHQ-9 total >= 20 => phq9_severe high', () => {
  const r = c.evaluateAssessment(assessment([3, 3, 3, 3, 3, 2, 2, 1, 0]));
  assert.equal(r.eventType, 'phq9_severe');
  assert.equal(r.severity, 'high');
  assert.equal(r.phq9Total, 20);
});

test('combined severe total + item 9 => one critical event with both reasons', () => {
  const r = c.evaluateAssessment(assessment([3, 3, 3, 3, 3, 3, 3, 3, 3]));
  assert.equal(r.severity, 'critical');
  assert.equal(r.reasons.length, 2);
});

test('under-reported total is corrected from items (fail safe)', () => {
  const r = c.evaluateAssessment(assessment([3, 3, 3, 3, 3, 3, 2, 0, 0], { phq9Score: 5 }));
  assert.equal(r.phq9Total, 20);
  assert.equal(r.eventType, 'phq9_severe');
});

test('alternative field spellings accepted', () => {
  assert.equal(c.extractPhq9({ phq9Total: 21 }).total, 21);
  assert.equal(c.extractPhq9({ phq9Item9: 2 }).item9, 2);
  assert.equal(c.extractPhq9({ type: 'phq9', answers: [0, 0, 0, 0, 0, 0, 0, 0, 2] }).item9, 2);
});

// Current shape (phq9_assessment_screen.dart): totalScore, item9, phq9Answers
test('current fields: totalScore / item9 / phq9Answers', () => {
  const cur = (answers, extra = {}) => ({
    patientId: 'p1', therapistId: 't1', type: 'phq9_gad7',
    totalScore: answers.reduce((a, b) => a + b, 0), item9: answers[8], phq9Answers: answers, ...extra,
  });
  assert.equal(c.evaluateAssessment(cur([0, 0, 0, 0, 0, 0, 0, 0, 2])).severity, 'critical');
  assert.equal(c.evaluateAssessment(cur([3, 3, 3, 3, 3, 3, 2, 0, 0])).eventType, 'phq9_severe');
  assert.equal(c.evaluateAssessment(cur([1, 1, 1, 1, 1, 1, 1, 1, 0])), null);
  // item9 field missing but answers show it: still critical
  const r = c.evaluateAssessment(cur([0, 0, 0, 0, 0, 0, 0, 0, 1], { item9: undefined, totalScore: 0 }));
  assert.equal(r.severity, 'critical');
});

test('max total across totalScore, phq9Score and both answer arrays', () => {
  const p = c.extractPhq9({
    type: 'phq9_gad7', totalScore: 5, phq9Score: 7,
    phq9Answers: [1, 1, 1, 1, 1, 1, 1, 1, 0],
    answers: { phq9: [3, 3, 3, 3, 3, 3, 3, 0, 1] },
  });
  assert.equal(p.total, 22);
  assert.equal(p.item9, 1);
});

test('totalScore ignored for non-PHQ assessment types', () => {
  assert.equal(c.extractPhq9({ type: 'gad7', totalScore: 21 }).total, null);
  assert.equal(c.extractPhq9({ totalScore: 21 }).total, 21);
});

test('assessment risk score alone => high_risk', () => {
  const r = c.evaluateAssessment({ riskScore: 80 });
  assert.equal(r.eventType, 'high_risk');
});

test('deterministic crisis ids', () => {
  assert.equal(c.crisisIdForDailyLog('abc'), 'dailylog_abc');
  assert.equal(c.crisisIdForAssessment('abc'), 'assessment_abc');
  assert.notEqual(c.crisisIdForDailyLog('abc'), c.crisisIdForAssessment('abc'));
});

test('severity ordering', () => {
  assert.equal(c.maxSeverity('high', 'critical'), 'critical');
  assert.equal(c.maxSeverity(null, 'medium'), 'medium');
  assert.equal(c.maxSeverity('high', 'medium'), 'high');
});

test('daily log with null riskScore / ML crisisText does not throw or alert', () => {
  assert.equal(c.evaluateDailyLog({ riskScore: null, wellbeingScore: null }), null);
  assert.equal(c.evaluateDailyLog({
    riskScore: null,
    mlSentiment: { crisisText: { severity: 'critical', triggerLayer: 'lexicon' } },
  }), null);
  assert.equal(c.evaluateDailyLog({ riskScore: null, mlRisk: { riskScore: 77 } }).eventType, 'high_risk');
});

test('planCrisisMerge: patient-created phq9 alert gets server facts, never un-acknowledged', () => {
  const existing = {
    patientId: 'p1', therapistId: 't1', eventType: 'phq9_severe', severity: 'high',
    acknowledged: true, acknowledgedBy: 't1', timestamp: 1,
  };
  const verified = c.evaluateAssessment({
    type: 'phq9_gad7', totalScore: 21, item9: 2, phq9Answers: [3, 3, 3, 3, 3, 2, 2, 0, 2],
  });
  const u = c.planCrisisMerge(existing, verified);
  assert.equal(u.severity, 'critical', 'escalates');
  assert.equal(u['serverVerified.totalScore'], 21);
  assert.equal(u['serverVerified.item9'], 2);
  for (const k of Object.keys(u)) {
    assert.ok(!/^acknowledged|^timestamp|^patientId|^therapistId/.test(k), `must not touch ${k}`);
  }
});

test('planCrisisMerge: never downgrades; idempotent on retry', () => {
  const verified = c.evaluateAssessment({ type: 'phq9', totalScore: 20, phq9Answers: [3, 3, 3, 3, 3, 3, 2, 0, 0] });
  assert.equal(verified.severity, 'high');
  const existing = { severity: 'critical', acknowledged: false };
  const u = c.planCrisisMerge(existing, verified);
  assert.equal(u.severity, undefined, 'critical is not downgraded to high');
  const after = { ...existing, serverVerified: {
    eventType: verified.eventType, severity: verified.severity, reasons: verified.reasons,
    totalScore: 20, item9: 0, riskScore: null,
  } };
  assert.equal(c.planCrisisMerge(after, verified), null, 'second run is a no-op');
});
