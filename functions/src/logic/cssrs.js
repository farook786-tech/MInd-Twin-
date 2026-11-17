'use strict';

/**
 * Columbia-Suicide Severity Rating Scale (C-SSRS) Screener, "Screen Version -
 * Recent" — pure triage. Mirrors lib/services/clinical_scoring.dart
 * (ClinicalScoring.triageCssrs); keep both in sync.
 *
 * Source: Posner K, Brown GK, Stanley B, et al. The Columbia-Suicide Severity
 * Rating Scale. Am J Psychiatry 2011;168(12):1266-1277. The Columbia Lighthouse
 * Project, https://cssrs.columbia.edu (free for clinical use).
 *
 * Questions (Q1-Q5: past month):
 *   q1 wish to be dead; q2 non-specific active suicidal thoughts;
 *   if q2 = yes: q3 thoughts of method, q4 intent, q5 plan with intent;
 *   q6 suicidal behaviour ever; if yes, q6Recent = within the past 3 months.
 * Published triage:
 *   any YES to Q1-Q2 only                 -> low      (offer resources)
 *   Q3 YES, or Q6 YES but > 3 months ago  -> moderate (clinician review soon)
 *   Q4 or Q5 YES, or Q6 YES in past 3 mo. -> high     (immediate safety assessment)
 * Fail-safe: Q6 = yes with unknown recency is treated as recent (high).
 */

const CSSRS_RISKS = Object.freeze(['none', 'low', 'moderate', 'high']);
const RISK_RANK = Object.freeze({ none: 0, low: 1, moderate: 2, high: 3 });

const ITEM_LABELS = Object.freeze({
  q1: 'Q1 = yes (wish to be dead, past month)',
  q2: 'Q2 = yes (non-specific active suicidal thoughts, past month)',
  q3: 'Q3 = yes (thoughts of method, past month)',
  q4: 'Q4 = yes (intent)',
  q5: 'Q5 = yes (plan with intent)',
  q6_recent: 'Q6 = yes (suicidal behaviour within past 3 months)',
  q6_lifetime: 'Q6 = yes (suicidal behaviour, more than 3 months ago)',
});

const yes = (v) => v === true;

/**
 * @param {object} answers {q1..q6, q6Recent} booleans (q3-q5/q6Recent may be null)
 * @return {{risk: string, positiveItems: string[]}|null} null if unusable
 */
function triageCssrs(answers) {
  if (!answers || typeof answers !== 'object') return null;
  const { q1, q2, q3, q4, q5, q6, q6Recent } = answers;
  if (typeof q1 !== 'boolean' || typeof q2 !== 'boolean' || typeof q6 !== 'boolean') return null;

  const positiveItems = [];
  if (yes(q1)) positiveItems.push('q1');
  if (yes(q2)) positiveItems.push('q2');
  if (yes(q3)) positiveItems.push('q3');
  if (yes(q4)) positiveItems.push('q4');
  if (yes(q5)) positiveItems.push('q5');
  if (yes(q6)) positiveItems.push(q6Recent === false ? 'q6_lifetime' : 'q6_recent');

  let risk;
  if (yes(q4) || yes(q5) || (yes(q6) && q6Recent !== false)) risk = 'high';
  else if (yes(q3) || (yes(q6) && q6Recent === false)) risk = 'moderate';
  else if (yes(q1) || yes(q2)) risk = 'low';
  else risk = 'none';
  return { risk, positiveItems };
}

/** The more severe of two risk strings (unknown values ignored). */
function maxRisk(a, b) {
  const ra = RISK_RANK[a];
  const rb = RISK_RANK[b];
  if (ra === undefined) return rb === undefined ? null : b;
  if (rb === undefined) return a;
  return ra >= rb ? a : b;
}

/**
 * Evaluates a `clinical_assessments` doc of type 'cssrs'. The stored
 * cssrsRisk (client-computed) and the recomputed triage are combined; the most
 * severe wins (fail safe).
 * @return {null|{eventType:string, severity:string, reasons:string[], cssrsRisk:string}}
 */
function evaluateCssrsAssessment(data) {
  if (!data || data.type !== 'cssrs') return null;
  const triage = triageCssrs(data.cssrsAnswers);
  const risk = maxRisk(triage ? triage.risk : null, data.cssrsRisk);
  if (risk !== 'high' && risk !== 'moderate') return null;
  const items = triage ? triage.positiveItems : [];
  const reasons = [`C-SSRS screener: ${risk.toUpperCase()} risk (Columbia triage)`,
    ...items.map((i) => `C-SSRS ${ITEM_LABELS[i]}`)];
  if (!triage) reasons.push('C-SSRS answers unreadable; stored risk used');
  return risk === 'high' ?
    { eventType: 'cssrs_high', severity: 'critical', reasons, cssrsRisk: risk } :
    { eventType: 'cssrs_moderate', severity: 'medium', reasons, cssrsRisk: risk };
}

module.exports = {
  CSSRS_RISKS,
  ITEM_LABELS,
  triageCssrs,
  maxRisk,
  evaluateCssrsAssessment,
};
