'use strict';

/**
 * Optional LLM narrative for the pre-session brief.
 *
 * Off unless BOTH: env AI_BRIEF_LLM_ENABLED=true AND the patient set
 * users/{patientId}.settings.aiSummaryConsent == true.
 *
 * Only a DE-IDENTIFIED projection of the deterministic brief is sent:
 *  - no name, email, phone, uid/doc ids, sources or calendar dates
 *    (dates are rendered relative: "3 days ago");
 *  - journal excerpts truncated (80 chars) and scrubbed of anything that
 *    looks like an email, phone number, URL, street address or long id.
 * The answer is post-validated; any doubt -> null (deterministic brief only).
 */

const axios = require('axios');
const {
  OPENROUTER_MODEL,
  GEMINI_MODEL,
  GEMINI_ENDPOINT,
  isConfiguredKey,
} = require('../config/aiModels');

const MAX_WORDS = 150;
const LLM_JOURNAL_EXCERPT_CHARS = 80;
const PROVIDER_TIMEOUT_MS = 20000;

const SYSTEM_PROMPT = [
  'You summarise structured monitoring data for a licensed mental-health clinician before a session.',
  'Write ONE neutral paragraph of at most 120 words.',
  'Use ONLY facts present in the JSON input. Do not add facts, numbers, dates, causes, interpretations or predictions.',
  'Never state or suggest a diagnosis or condition name.',
  'Never mention, suggest or adjust any medication, drug, dose or treatment; never give recommendations.',
  'Mention every item in "flags" first, then notable changes, then data gaps.',
  'Use relative time expressions exactly as written in the input (e.g. "3 days ago").',
  'Refer to the person only as "the patient". No headings, lists or markdown.',
].join(' ');

// --------------------------------------------------------- de-identification

const EMAIL_RE = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const URL_RE = /\b(?:https?:\/\/|www\.)\S+/gi;
// Candidate phone numbers; replaced only when they contain >= 7 digits.
const PHONE_RE = /\+?\d[\d\s().-]{5,}\d/g;
const ADDRESS_RE = /\b\d{1,5}[A-Za-z]?(?:[ ,]+[A-Za-z0-9.'-]+){0,4}[ ,]+(?:street|st|road|rd|avenue|ave|lane|ln|drive|dr|boulevard|blvd|nagar|marg|colony|sector|block|apartment|apt|flat|house|floor)\b\.?/gi;
const PINCODE_RE = /\b\d{6}\b/g;
const LONG_ID_RE = /\b(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{16,}\b/g;

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * @param {string} text
 * @param {{names?: string[], freeText?: boolean}} [opts] identifying words to remove
 *   (patient name parts); freeText=false skips the phone/address/PIN patterns
 */
function scrubText(text, opts = {}) {
  let t = String(text || '');
  t = t.replace(EMAIL_RE, '[email removed]');
  t = t.replace(URL_RE, '[link removed]');
  if (opts.freeText !== false) {
    // Patient-written text only: structured statistics (e.g. step counts)
    // must not be mangled by the phone / PIN-code patterns.
    t = t.replace(ADDRESS_RE, '[address removed]');
    t = t.replace(PHONE_RE, (m) => ((m.match(/\d/g) || []).length >= 7 ? '[number removed]' : m));
    t = t.replace(PINCODE_RE, '[number removed]');
  }
  t = t.replace(LONG_ID_RE, '[id removed]');
  for (const n of opts.names || []) {
    if (typeof n !== 'string' || n.trim().length < 2) continue;
    t = t.replace(new RegExp(`\\b${escapeRe(n.trim())}\\b`, 'gi'), 'the patient');
  }
  return t;
}

/** Name parts / identifiers from users/{patientId} to scrub everywhere. */
function identifyingWords(patient = {}) {
  const words = [];
  for (const k of ['name', 'displayName', 'firstName', 'lastName']) {
    const v = patient[k];
    if (typeof v !== 'string') continue;
    words.push(v);
    for (const part of v.split(/\s+/)) if (part.length >= 2) words.push(part);
  }
  for (const k of ['email', 'phone']) if (typeof patient[k] === 'string' && patient[k]) words.push(patient[k]);
  return [...new Set(words)].sort((a, b) => b.length - a.length);
}

/**
 * @param {object} relativeBrief brief built with dateMode 'relative' and short journal excerpts
 * @param {object} patient users/{patientId} data
 * @return {{periodLengthDays: number, flags: string[], sections: {title: string, items: string[]}[], dataGaps: string[]}}
 */
function deidentifyBrief(relativeBrief, patient = {}) {
  const names = identifyingWords(patient);
  const clean = (s) => scrubText(s, { names, freeText: false });
  const cleanFree = (s) => scrubText(s, { names, freeText: true });
  return {
    periodLengthDays: relativeBrief.period.days,
    periodBasis: relativeBrief.period.basis === 'last_completed_session' ? 'since last completed session' : 'last 14 days',
    flags: relativeBrief.flags.map((f) => clean(f.text)),
    sections: relativeBrief.sections
      .filter((s) => s.items.length)
      .map((s) => ({
        title: s.title,
        items: s.items.map((i) => (i.source && i.source.collection === 'journal_entries' ? cleanFree(i.text) : clean(i.text))),
      })),
    dataGaps: relativeBrief.dataGaps.map(clean),
  };
}

// ------------------------------------------------------------- validation

// Psychotropic and common medication names plus dose / prescribing language.
const MEDICATION_TERMS = [
  'medication', 'medicine', 'medicat', 'drug', 'dose', 'dosage', 'dosing', 'mg', 'mcg', 'milligram', 'tablet', 'pill',
  'capsule', 'prescri', 'titrat', 'taper', 'ssri', 'snri', 'maoi', 'antidepressant', 'antipsychotic', 'anxiolytic',
  'benzodiazepine', 'stimulant', 'mood stabili', 'sertraline', 'fluoxetine', 'escitalopram', 'citalopram',
  'paroxetine', 'fluvoxamine', 'venlafaxine', 'desvenlafaxine', 'duloxetine', 'bupropion', 'mirtazapine',
  'trazodone', 'vortioxetine', 'agomelatine', 'amitriptyline', 'nortriptyline', 'imipramine', 'clomipramine',
  'lithium', 'valpro', 'divalproex', 'lamotrigine', 'carbamazepine', 'quetiapine', 'olanzapine', 'risperidone',
  'aripiprazole', 'clozapine', 'haloperidol', 'lurasidone', 'ziprasidone', 'paliperidone', 'clonazepam',
  'lorazepam', 'alprazolam', 'diazepam', 'chlordiazepoxide', 'zolpidem', 'zopiclone', 'melatonin', 'buspirone',
  'hydroxyzine', 'propranolol', 'methylphenidate', 'amphetamine', 'atomoxetine', 'modafinil', 'ketamine',
  'esketamine', 'naltrexone', 'disulfiram', 'gabapentin', 'pregabalin', 'prozac', 'zoloft', 'lexapro', 'xanax',
  'valium', 'ativan', 'klonopin', 'seroquel', 'abilify', 'wellbutrin', 'cymbalta', 'effexor', 'remeron',
];
const WHOLE_WORD_TERMS = new Set(['pill', 'mg', 'mcg', 'tablet', 'dose', 'drug', 'capsule', 'taper', 'ocd', 'mdd', 'adhd', 'ptsd']);
const DIAGNOSIS_TERMS = [
  'diagnosis', 'diagnoses', 'diagnose', 'diagnosed', 'disorder', 'mdd', 'gad ', 'ptsd', 'bipolar', 'schizo', 'psychosis', 'psychotic', 'borderline',
  'adhd', 'ocd', 'depressive episode', 'suffers from', 'consistent with', 'indicative of', 'suggests that',
];
const ADVICE_TERMS = ['recommend', 'should consider', 'consider starting', 'consider increasing', 'advise', 'prognos', 'likely to', 'will likely'];

function numbersIn(text) {
  return (String(text).match(/\d+(?:\.\d+)?/g) || []).map((n) => String(Number(n)));
}

/**
 * @return {{ok: true, text: string} | {ok: false, reason: string}}
 */
function validateNarrative(raw, deidInput) {
  if (typeof raw !== 'string') return { ok: false, reason: 'empty_response' };
  const text = raw.replace(/\s+/g, ' ').trim();
  if (!text) return { ok: false, reason: 'empty_response' };
  const words = text.split(' ').length;
  if (words > MAX_WORDS) return { ok: false, reason: 'too_long' };
  const lower = ` ${text.toLowerCase()} `;
  const hit = (terms) => terms.some((t) => {
    // Short complete words match only as whole words (optionally plural) so
    // "pillow" or "mgmt" don't trip the filter; stems ("prescri", "titrat")
    // keep prefix matching.
    const re = WHOLE_WORD_TERMS.has(t)
      ? new RegExp(`(^|[^a-z])${escapeRe(t)}s?([^a-z]|$)`, 'i')
      : new RegExp(`(^|[^a-z])${escapeRe(t)}`, 'i');
    return re.test(lower);
  });
  if (hit(MEDICATION_TERMS)) return { ok: false, reason: 'mentions_medication' };
  if (hit(DIAGNOSIS_TERMS)) return { ok: false, reason: 'mentions_diagnosis' };
  if (hit(ADVICE_TERMS)) return { ok: false, reason: 'gives_advice' };
  if (EMAIL_RE.test(text) || /\[(?:email|number|address|link|id) removed\]/i.test(text)) {
    EMAIL_RE.lastIndex = 0;
    return { ok: false, reason: 'contains_identifier' };
  }
  EMAIL_RE.lastIndex = 0;
  const allowed = new Set(numbersIn(JSON.stringify(deidInput)));
  for (const n of numbersIn(text)) {
    if (!allowed.has(n)) return { ok: false, reason: 'number_not_in_input' };
  }
  return { ok: true, text };
}

// --------------------------------------------------------------- providers

/** OpenRouter first, then Gemini (same providers/models as routes/gemini.js). Returns text or null. */
async function callBriefLlm({ system, user, env = process.env, http = axios }) {
  const openRouterKey = env.OPENROUTER_API_KEY;
  if (isConfiguredKey(openRouterKey)) {
    try {
      const res = await http.post(
        'https://openrouter.ai/api/v1/chat/completions',
        {
          model: OPENROUTER_MODEL,
          messages: [{ role: 'system', content: system }, { role: 'user', content: user }],
          max_tokens: 300,
          temperature: 0.1,
        },
        { headers: { Authorization: `Bearer ${openRouterKey}` }, timeout: PROVIDER_TIMEOUT_MS }
      );
      const text = (res.data?.choices?.[0]?.message?.content || '').trim();
      if (text) return text;
    } catch (err) {
      console.warn('[SessionBrief] OpenRouter failed:', err.response?.status || err.code || 'error');
    }
  }
  const geminiKey = env.GEMINI_API_KEY;
  if (isConfiguredKey(geminiKey)) {
    try {
      const res = await http.post(
        `${GEMINI_ENDPOINT}/${GEMINI_MODEL}:generateContent`,
        {
          systemInstruction: { parts: [{ text: system }] },
          contents: [{ role: 'user', parts: [{ text: user }] }],
          generationConfig: { temperature: 0.1, maxOutputTokens: 300 },
        },
        { headers: { 'x-goog-api-key': geminiKey }, timeout: PROVIDER_TIMEOUT_MS }
      );
      const text = res.data?.candidates?.[0]?.content?.parts?.map((p) => p.text).join('').trim();
      if (text) return text;
    } catch (err) {
      console.warn('[SessionBrief] Gemini failed:', err.response?.status || err.code || 'error');
    }
  }
  return null;
}

// ------------------------------------------------------------------- main

function narrativeGate(env, patient) {
  if (String(env.AI_BRIEF_LLM_ENABLED || '').toLowerCase() !== 'true') {
    return { enabled: false, reason: 'disabled_on_server' };
  }
  const settings = patient && typeof patient.settings === 'object' && patient.settings ? patient.settings : {};
  if (settings.aiSummaryConsent !== true) return { enabled: false, reason: 'no_patient_consent' };
  return { enabled: true, reason: null };
}

/**
 * @param {object} p
 * @param {object} p.relativeBrief deterministic brief built with dateMode 'relative'
 * @param {object} p.patient users/{patientId} data
 * @param {object} [p.env]
 * @param {Function} [p.callLlm] ({system, user}) => Promise<string|null>
 * @return {Promise<{narrative: string|null, reason: string|null}>}
 */
async function generateNarrative({ relativeBrief, patient, env = process.env, callLlm = callBriefLlm }) {
  const gate = narrativeGate(env, patient);
  if (!gate.enabled) return { narrative: null, reason: gate.reason };
  const deid = deidentifyBrief(relativeBrief, patient);
  let raw;
  try {
    raw = await callLlm({ system: SYSTEM_PROMPT, user: JSON.stringify(deid), env });
  } catch {
    raw = null;
  }
  if (!raw) return { narrative: null, reason: 'provider_unavailable' };
  const v = validateNarrative(raw, deid);
  if (!v.ok) return { narrative: null, reason: `rejected_${v.reason}` };
  return { narrative: v.text, reason: null };
}

module.exports = {
  generateNarrative,
  narrativeGate,
  deidentifyBrief,
  validateNarrative,
  scrubText,
  callBriefLlm,
  SYSTEM_PROMPT,
  MAX_WORDS,
  LLM_JOURNAL_EXCERPT_CHARS,
};
