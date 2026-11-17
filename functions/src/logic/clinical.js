'use strict';

/**
 * Pure crisis-detection logic for daily logs and clinical assessments.
 *
 * Field names come from the patient app (current: totalScore, item9,
 * phq9Answers [9 ints]; legacy: phq9Score, answers.phq9):
 *  - daily_logs (lib/screens/patient/daily_checkin_screen.dart):
 *      riskScore (0-100), later merged mlRisk.riskScore (0-100)
 *  - clinical_assessments (lib/screens/patient/phq9_assessment_screen.dart):
 *      phq9Score (total), answers.phq9 = [9 ints 0..3] (item 9 = index 8),
 *      gad7Score, type: 'phq9_gad7'
 * A few alternative spellings are accepted defensively; when several sources
 * disagree, the most severe value wins (fail safe).
 */

const { SEVERITY_RANK } = require('./constants');

const RISK_SCORE_CRISIS = 75;
const RISK_SCORE_CRITICAL = 90;
const PHQ9_SEVERE_TOTAL = 20;

function num(v) {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v);
  return null;
}

function maxOf(values) {
  const finite = values.filter((v) => v !== null);
  return finite.length ? Math.max(...finite) : null;
}

function maxSeverity(a, b) {
  if (!a) return b;
  if (!b) return a;
  return SEVERITY_RANK[a] >= SEVERITY_RANK[b] ? a : b;
}

/** Highest risk score found on a daily log (0-100) or null. */
function extractRiskScore(data) {
  if (!data) return null;
  return maxOf([
    num(data.riskScore),
    num(data.mlRisk && data.mlRisk.riskScore),
  ]);
}

/**
 * @param {object} data assessment document
 * @return {{total: number|null, item9: number|null, items: number[]|null}}
 */
function extractPhq9(data) {
  if (!data) return { total: null, item9: null, items: null };
  // Every 9-item answer array present is considered; the most severe wins.
  const candidates = [
    data.phq9Answers,
    data.answers && data.answers.phq9,
    Array.isArray(data.answers) && /phq/i.test(String(data.type || '')) ? data.answers : null,
  ];
  let items = null;
  let computedTotal = null;
  const itemNines = [];
  for (const c of candidates) {
    if (!Array.isArray(c) || c.length !== 9) continue;
    const parsed = c.map(num);
    itemNines.push(parsed[8]);
    if (parsed.every((v) => v !== null && v >= 0 && v <= 3)) {
      const sum = parsed.reduce((a, b) => a + b, 0);
      if (computedTotal === null || sum > computedTotal) {
        computedTotal = sum;
        items = parsed;
      }
    }
  }
  const validItems = items !== null;
  // totalScore is the PHQ-9 total for PHQ assessments (current app); it is
  // ignored for non-PHQ types (e.g. a GAD-7-only form) to avoid mislabeling.
  const typeStr = String(data.type || '');
  const totalScoreIsPhq = typeStr === '' || /phq/i.test(typeStr);
  const total = maxOf([
    totalScoreIsPhq ? num(data.totalScore) : null,
    num(data.phq9Score),
    num(data.phq9Total),
    num(data.phq9 && typeof data.phq9 === 'object' ? data.phq9.total : null),
    computedTotal,
  ]);
  const item9 = maxOf([
    num(data.item9),
    num(data.phq9Item9),
    ...itemNines,
  ]);
  return { total, item9, items: validItems ? items : null };
}

/**
 * @return {null|{eventType:string, severity:string, reasons:string[]}}
 */
function evaluateDailyLog(data) {
  const risk = extractRiskScore(data);
  if (risk === null || risk < RISK_SCORE_CRISIS) return null;
  return {
    eventType: 'high_risk',
    severity: risk >= RISK_SCORE_CRITICAL ? 'critical' : 'high',
    reasons: [`Daily check-in risk score ${Math.round(risk)}/100 (threshold ${RISK_SCORE_CRISIS})`],
    riskScore: risk,
  };
}

/**
 * Raises ONE combined evaluation per assessment.
 *  - PHQ-9 item 9 > 0 (any suicidal-ideation answer) => phq9_severe, critical
 *  - PHQ-9 total >= 20                               => phq9_severe, high
 *  - riskScore >= 75                                 => high_risk, high/critical
 * @return {null|{eventType:string, severity:string, reasons:string[]}}
 */
function evaluateAssessment(data) {
  const { total, item9 } = extractPhq9(data);
  const risk = extractRiskScore(data);
  const reasons = [];
  let severity = null;
  let eventType = null;

  if (item9 !== null && item9 > 0) {
    reasons.push(`PHQ-9 item 9 (thoughts of self-harm) answered ${item9}/3`);
    severity = maxSeverity(severity, 'critical');
    eventType = 'phq9_severe';
  }
  if (total !== null && total >= PHQ9_SEVERE_TOTAL) {
    reasons.push(`PHQ-9 total ${total}/27 (severe, threshold ${PHQ9_SEVERE_TOTAL})`);
    severity = maxSeverity(severity, 'high');
    eventType = 'phq9_severe';
  }
  if (risk !== null && risk >= RISK_SCORE_CRISIS) {
    reasons.push(`Risk score ${Math.round(risk)}/100 (threshold ${RISK_SCORE_CRISIS})`);
    severity = maxSeverity(severity, risk >= RISK_SCORE_CRITICAL ? 'critical' : 'high');
    eventType = eventType || 'high_risk';
  }
  if (!reasons.length) return null;
  return { eventType, severity, reasons, phq9Total: total, phq9Item9: item9 };
}

function describeClinicalAlert(patientName, source, evaluation) {
  const name = patientName || 'Patient';
  const what = source === 'assessment' ? 'assessment' : 'daily check-in';
  const title = evaluation.eventType === 'phq9_severe' ?
    `${evaluation.severity === 'critical' ? 'URGENT: ' : ''}PHQ-9 alert: ${name}` :
    `High risk check-in: ${name}`;
  const message = `${name}'s ${what} needs review: ${evaluation.reasons.join('; ')}.`;
  return { title, message };
}

/**
 * When a crisis doc with the deterministic id already exists (patient app
 * wrote it first, or a retry), returns the field updates to apply, or null.
 * Never touches acknowledged*, timestamp, patientId, therapistId. Severity can
 * only escalate. Field paths are dotted (Firestore update syntax).
 * @param {object} existing current crisis doc data
 * @param {{eventType:string, severity:string, reasons:string[],
 *   phq9Total?:number|null, phq9Item9?:number|null, riskScore?:number}} verified
 * @return {object|null}
 */
function planCrisisMerge(existing, verified) {
  if (!existing || !verified) return null;
  const prev = existing.serverVerified || {};
  const update = {};
  const fields = {
    eventType: verified.eventType,
    severity: verified.severity,
    reasons: verified.reasons,
    totalScore: verified.phq9Total === undefined ? null : verified.phq9Total,
    item9: verified.phq9Item9 === undefined ? null : verified.phq9Item9,
    riskScore: verified.riskScore === undefined ? null : verified.riskScore,
  };
  for (const [k, v] of Object.entries(fields)) {
    if (JSON.stringify(prev[k]) !== JSON.stringify(v)) update[`serverVerified.${k}`] = v;
  }
  const current = SEVERITY_RANK[existing.severity] ? existing.severity : null;
  if (maxSeverity(current, verified.severity) !== current) {
    update.severity = verified.severity;
  }
  return Object.keys(update).length ? update : null;
}

const crisisIdForDailyLog = (id) => `dailylog_${id}`;
const crisisIdForAssessment = (id) => `assessment_${id}`;

module.exports = {
  RISK_SCORE_CRISIS,
  RISK_SCORE_CRITICAL,
  PHQ9_SEVERE_TOTAL,
  maxSeverity,
  extractRiskScore,
  extractPhq9,
  evaluateDailyLog,
  evaluateAssessment,
  describeClinicalAlert,
  planCrisisMerge,
  crisisIdForDailyLog,
  crisisIdForAssessment,
};
