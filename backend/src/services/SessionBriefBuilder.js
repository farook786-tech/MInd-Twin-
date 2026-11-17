'use strict';

/**
 * Pre-session brief: DETERMINISTIC builder (no LLM, no network, no Firestore).
 *
 * Input: plain records {id, data} already read by the route (Admin SDK).
 * Output: {generatedAt, period, sections: [{title, items: [{text, source}]}],
 *          flags: [{text, source}], dataGaps: [string]}
 *
 * Rules (docs/CLINICAL_SAFETY_CASE.md):
 *  - every item carries its source {collection, docId, field, at};
 *  - only facts present in the data (counts, values, dates, means/ranges);
 *  - neutral wording, no interpretation, no treatment/medication suggestions;
 *  - missing data is reported as a data gap, never as "normal" or "low".
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_LOOKBACK_DAYS = 14;
const MAX_LOOKBACK_DAYS = 90;
const STALE_DAYS = 14;
const MAX_LISTED_ASSESSMENTS = 10;
const MAX_LISTED_EVENTS = 20;
const MAX_LISTED_JOURNALS = 10;
const DEFAULT_JOURNAL_EXCERPT_CHARS = 200;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const SECTION = Object.freeze({
  instruments: 'Instruments (PHQ-9, GAD-7, C-SSRS)',
  checkins: 'Daily check-ins',
  alerts: 'Alerts and crisis events',
  vitals: 'Vitals (wearable)',
  journal: 'Journal entries shared with you',
  appointments: 'Appointments',
  adherence: 'Adherence',
});

const EVENT_LABELS = Object.freeze({
  checkin_crisis: 'Check-in crisis alert',
  sos: 'SOS button pressed',
  chat_crisis: 'Crisis language in AI chat',
  high_risk: 'Check-in wellbeing indicator alert',
  phq9_severe: 'PHQ-9 alert',
  cssrs_high: 'C-SSRS high-risk alert',
  cssrs_moderate: 'C-SSRS moderate-risk alert',
  vital_high: 'Vital above threshold',
  vital_low: 'Vital below threshold',
});

const CSSRS_ITEM_LABELS = Object.freeze({
  q1: 'Q1 = yes (wish to be dead, past month)',
  q2: 'Q2 = yes (non-specific active suicidal thoughts, past month)',
  q3: 'Q3 = yes (thoughts of method, past month)',
  q4: 'Q4 = yes (intent)',
  q5: 'Q5 = yes (plan with intent)',
  q6_recent: 'Q6 = yes (suicidal behaviour, within past 3 months)',
  q6_lifetime: 'Q6 = yes (suicidal behaviour, more than 3 months ago)',
});

const CHECKIN_FIELDS = Object.freeze([
  { field: 'moodScore', label: 'Mood score' },
  { field: 'sleepScore', label: 'Sleep score' },
  { field: 'energyScore', label: 'Energy score' },
  { field: 'wellbeingScore', label: 'Wellbeing score (0-100)' },
  { field: 'riskScore', label: 'Check-in wellbeing indicator (self-report heuristic, not diagnostic; 0-100)' },
]);

// --------------------------------------------------------------- utilities

/** Firestore Timestamp | Date | millis | ISO string | {_seconds} -> millis or null. */
function toMillis(v) {
  if (v === null || v === undefined) return null;
  if (typeof v.toMillis === 'function') {
    const ms = v.toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  if (v instanceof Date) return Number.isFinite(v.getTime()) ? v.getTime() : null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string') {
    const ms = Date.parse(v);
    return Number.isFinite(ms) ? ms : null;
  }
  if (typeof v === 'object' && typeof v._seconds === 'number') {
    return v._seconds * 1000 + Math.floor((v._nanoseconds || 0) / 1e6);
  }
  return null;
}

function isoOrNull(ms) {
  return ms === null || ms === undefined ? null : new Date(ms).toISOString();
}

function clampTz(tzOffsetMinutes) {
  const n = Number(tzOffsetMinutes);
  if (!Number.isFinite(n)) return 0;
  return Math.max(-840, Math.min(840, Math.round(n)));
}

/** Patient-local day index (days since epoch in the given UTC offset). */
function localDayIndex(ms, tz) {
  return Math.floor((ms + tz * 60000) / DAY_MS);
}

function localDateKey(ms, tz) {
  const d = new Date(ms + tz * 60000);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** 'yyyy-MM-dd' (patient-local) -> millis at local noon, or null. */
function dateKeyToMillis(key, tz) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ''));
  if (!m) return null;
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 12) - tz * 60000;
}

/**
 * 'absolute' -> "Nov 2"; 'relative' -> "today" / "3 days ago" / "in 2 days"
 * (used for the de-identified LLM input: no calendar dates leave the server).
 */
function makeDateFormatter({ mode, nowMs, tz }) {
  if (mode === 'relative') {
    const today = localDayIndex(nowMs, tz);
    return (ms) => {
      const diff = today - localDayIndex(ms, tz);
      if (diff === 0) return 'today';
      if (diff === 1) return '1 day ago';
      if (diff > 1) return `${diff} days ago`;
      if (diff === -1) return 'in 1 day';
      return `in ${-diff} days`;
    };
  }
  return (ms) => {
    const d = new Date(ms + tz * 60000);
    return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
  };
}

function round1(n) {
  return Math.round(n * 10) / 10;
}

function fmtNum(n) {
  const r = round1(n);
  return Number.isInteger(r) ? String(r) : r.toFixed(1);
}

function isIntIn(v, lo, hi) {
  return typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi;
}

function src(collection, docId, field, atMs, extra) {
  const s = { collection, docId: docId || null, field: field || null, at: isoOrNull(atMs) };
  return extra ? { ...s, ...extra } : s;
}

function phq9Band(total) {
  if (total >= 20) return 'severe';
  if (total >= 15) return 'moderately severe';
  if (total >= 10) return 'moderate';
  if (total >= 5) return 'mild';
  return 'minimal';
}

function gad7Band(total) {
  if (total >= 15) return 'severe';
  if (total >= 10) return 'moderate';
  if (total >= 5) return 'mild';
  return 'minimal';
}

function pluralDays(n) {
  return n === 1 ? '1 day' : `${n} days`;
}

// ------------------------------------------------------------------ period

/**
 * Period = since the last COMPLETED session with this therapist (capped at
 * 90 days), else the last 14 days.
 */
function choosePeriod({ nowMs, appointments = [], therapistId }) {
  let last = null;
  for (const a of appointments) {
    const d = a.data || {};
    if (d.status !== 'completed') continue;
    if (therapistId && d.therapistId && d.therapistId !== therapistId) continue;
    const at = toMillis(d.scheduledAt);
    if (at === null || at > nowMs) continue;
    if (!last || at > last.at) last = { id: a.id, at };
  }
  if (last) {
    const floor = nowMs - MAX_LOOKBACK_DAYS * DAY_MS;
    return {
      fromMs: Math.max(last.at, floor),
      toMs: nowMs,
      basis: 'last_completed_session',
      lastSessionId: last.id,
      lastSessionAtMs: last.at,
      capped: last.at < floor,
    };
  }
  return {
    fromMs: nowMs - DEFAULT_LOOKBACK_DAYS * DAY_MS,
    toMs: nowMs,
    basis: 'default_14_days',
    lastSessionId: null,
    lastSessionAtMs: null,
    capped: false,
  };
}

// ------------------------------------------------------------- extraction

function assessmentAt(d) {
  return toMillis(d.timestamp) ?? toMillis(d.clientCreatedAt);
}

/** -> {phq9: [], gad7: [], cssrs: [], invalid: n}, each sorted oldest first. */
function extractInstruments(records) {
  const out = { phq9: [], gad7: [], cssrs: [], invalid: 0 };
  for (const r of records || []) {
    const d = r.data || {};
    const at = assessmentAt(d);
    if (at === null) {
      out.invalid += 1;
      continue;
    }
    if (d.type === 'cssrs') {
      if (['none', 'low', 'moderate', 'high'].includes(d.cssrsRisk)) {
        out.cssrs.push({ id: r.id, at, risk: d.cssrsRisk, answers: d.cssrsAnswers || {} });
      } else {
        out.invalid += 1;
      }
      continue;
    }
    const phqField = isIntIn(d.totalScore, 0, 27) ? 'totalScore' : (isIntIn(d.phq9Score, 0, 27) ? 'phq9Score' : null);
    if (phqField) {
      let item9 = isIntIn(d.item9, 0, 3) ? d.item9 : null;
      if (item9 === null && Array.isArray(d.phq9Answers) && isIntIn(d.phq9Answers[8], 0, 3)) item9 = d.phq9Answers[8];
      out.phq9.push({ id: r.id, at, total: d[phqField], field: phqField, item9 });
    } else if (d.totalScore !== undefined || d.phq9Score !== undefined) {
      out.invalid += 1;
    }
    if (isIntIn(d.gad7Score, 0, 21)) {
      out.gad7.push({ id: r.id, at, total: d.gad7Score, field: 'gad7Score' });
    } else if (d.gad7Score !== undefined && d.gad7Score !== null) {
      out.invalid += 1;
    }
  }
  for (const k of ['phq9', 'gad7', 'cssrs']) out[k].sort((a, b) => a.at - b.at);
  return out;
}

function cssrsYesItems(a) {
  const yes = [];
  for (const q of ['q1', 'q2', 'q3', 'q4', 'q5']) if (a[q] === true) yes.push(CSSRS_ITEM_LABELS[q]);
  if (a.q6 === true) yes.push(a.q6Recent === false ? CSSRS_ITEM_LABELS.q6_lifetime : CSSRS_ITEM_LABELS.q6_recent);
  return yes;
}

// ------------------------------------------------------------- sections

function scoreSeriesItems({ name, list, prior, band, collection, fmt, nowMs, items, gaps }) {
  if (list.length === 0) {
    gaps.push(`No ${name} completed in this period.`);
    if (prior) {
      items.push({
        text: `Most recent ${name} before this period: ${prior.total} (${band(prior.total)}) on ${fmt(prior.at)}.`,
        source: src(collection, prior.id, prior.field, prior.at),
      });
    }
  } else {
    const shown = list.slice(-MAX_LISTED_ASSESSMENTS);
    if (list.length > shown.length) {
      items.push({
        text: `${list.length} ${name} results in this period; the ${shown.length} most recent are listed.`,
        source: src(collection, list[list.length - 1].id, list[0].field, list[list.length - 1].at),
      });
    }
    for (const s of shown) {
      items.push({
        text: `${name} = ${s.total} (${band(s.total)}) on ${fmt(s.at)}.`,
        source: src(collection, s.id, s.field, s.at),
      });
    }
    const latest = list[list.length - 1];
    const baseline = prior || (list.length >= 2 ? list[0] : null);
    if (baseline && baseline.id !== latest.id) {
      const span = `(${fmt(baseline.at)} → ${fmt(latest.at)})`;
      let text;
      if (latest.total > baseline.total) text = `${name} rose from ${baseline.total} to ${latest.total} ${span}.`;
      else if (latest.total < baseline.total) text = `${name} fell from ${baseline.total} to ${latest.total} ${span}.`;
      else text = `${name} unchanged at ${latest.total} ${span}.`;
      items.push({
        text,
        source: src(collection, latest.id, latest.field, latest.at),
        comparedWith: src(collection, baseline.id, baseline.field, baseline.at),
      });
    }
  }
  const newest = list.length ? list[list.length - 1] : prior;
  if (newest) {
    const ageDays = Math.floor((nowMs - newest.at) / DAY_MS);
    if (ageDays > STALE_DAYS) {
      gaps.push(`Latest ${name} is ${ageDays} days old (older than the ${STALE_DAYS}-day recency window).`);
    }
  } else {
    gaps.push(`No ${name} on record.`);
  }
}

function buildInstruments({ inPeriod, prior, fmt, nowMs, flags, gaps }) {
  const items = [];
  const latestPrior = (arr) => (arr.length ? arr[arr.length - 1] : null);

  scoreSeriesItems({
    name: 'PHQ-9', list: inPeriod.phq9, prior: latestPrior(prior.phq9), band: phq9Band,
    collection: 'clinical_assessments', fmt, nowMs, items, gaps,
  });
  for (const s of inPeriod.phq9) {
    if (s.item9 !== null && s.item9 > 0) {
      const item = {
        text: `PHQ-9 item 9 (thoughts of death or self-harm) = ${s.item9} on ${fmt(s.at)}.`,
        source: src('clinical_assessments', s.id, 'item9', s.at),
      };
      items.push(item);
      flags.push(item);
    }
    if (s.total >= 20) {
      flags.push({
        text: `PHQ-9 = ${s.total} (severe range) on ${fmt(s.at)}.`,
        source: src('clinical_assessments', s.id, s.field, s.at),
      });
    }
  }

  scoreSeriesItems({
    name: 'GAD-7', list: inPeriod.gad7, prior: latestPrior(prior.gad7), band: gad7Band,
    collection: 'clinical_assessments', fmt, nowMs, items, gaps,
  });

  const cssrsPrior = latestPrior(prior.cssrs);
  if (inPeriod.cssrs.length === 0) {
    gaps.push('No C-SSRS screener completed in this period.');
    if (cssrsPrior) {
      items.push({
        text: `Most recent C-SSRS screener before this period: risk ${cssrsPrior.risk} on ${fmt(cssrsPrior.at)}.`,
        source: src('clinical_assessments', cssrsPrior.id, 'cssrsRisk', cssrsPrior.at),
      });
    }
  }
  for (const c of inPeriod.cssrs.slice(-MAX_LISTED_ASSESSMENTS)) {
    const yes = cssrsYesItems(c.answers);
    const item = {
      text: `C-SSRS screener on ${fmt(c.at)}: risk ${c.risk}` +
        (yes.length ? `; ${yes.join('; ')}.` : '; all answers no.'),
      source: src('clinical_assessments', c.id, 'cssrsRisk', c.at),
    };
    items.push(item);
    if (c.risk === 'high' || c.risk === 'moderate') flags.push(item);
  }
  return { title: SECTION.instruments, items };
}

function buildCheckins({ logs, period, fmt, flags, gaps }) {
  const items = [];
  const inPeriod = logs.filter((l) => l.at >= period.fromMs && l.at <= period.toMs);
  if (inPeriod.length === 0) {
    gaps.push('No daily check-ins in this period.');
    return { title: SECTION.checkins, items };
  }
  const latest = inPeriod[inPeriod.length - 1];
  items.push({
    text: `${inPeriod.length} check-in${inPeriod.length === 1 ? '' : 's'} between ${fmt(inPeriod[0].at)} and ${fmt(latest.at)}.`,
    source: src('daily_logs', latest.id, 'timestamp', latest.at, { docIds: inPeriod.slice(-50).map((l) => l.id) }),
  });
  for (const { field, label } of CHECKIN_FIELDS) {
    const vals = inPeriod
      .filter((l) => typeof l.data[field] === 'number' && Number.isFinite(l.data[field]))
      .map((l) => ({ id: l.id, at: l.at, v: l.data[field] }));
    if (vals.length === 0) continue;
    const nums = vals.map((x) => x.v);
    const mean = nums.reduce((a, b) => a + b, 0) / nums.length;
    const lastV = vals[vals.length - 1];
    let text = `${label}: ${vals.length} value${vals.length === 1 ? '' : 's'}, mean ${fmtNum(mean)}, ` +
      `range ${fmtNum(Math.min(...nums))}-${fmtNum(Math.max(...nums))}; latest ${fmtNum(lastV.v)} on ${fmt(lastV.at)}`;
    if (vals.length >= 4) {
      const half = Math.floor(vals.length / 2);
      const m1 = nums.slice(0, half).reduce((a, b) => a + b, 0) / half;
      const m2 = nums.slice(half).reduce((a, b) => a + b, 0) / (nums.length - half);
      text += `; mean of earlier half ${fmtNum(m1)}, later half ${fmtNum(m2)}`;
    }
    items.push({
      text: `${text}.`,
      source: src('daily_logs', lastV.id, field, lastV.at, { docIds: vals.slice(-50).map((x) => x.id) }),
    });
    if (field === 'riskScore') {
      for (const x of vals) {
        if (x.v >= 75) {
          flags.push({
            text: `Check-in wellbeing indicator ${fmtNum(x.v)} on ${fmt(x.at)} (at or above the 75 alert threshold; not diagnostic).`,
            source: src('daily_logs', x.id, 'riskScore', x.at),
          });
        }
      }
    }
  }
  return { title: SECTION.checkins, items };
}

function buildAlerts({ events, period, fmt, flags, gaps }) {
  const items = [];
  const sorted = [...events].sort((a, b) => b.at - a.at);
  const inPeriod = sorted.filter((e) => e.at >= period.fromMs && e.at <= period.toMs);
  const describe = (e) => {
    const d = e.data;
    const label = EVENT_LABELS[d.eventType] || `Alert (${String(d.eventType || 'unknown').slice(0, 40)})`;
    let text = `${label}, severity ${String(d.severity || 'unspecified').slice(0, 20)}, on ${fmt(e.at)}`;
    const v = d.vital;
    if (v && typeof v === 'object' && typeof v.value === 'number') {
      const unit = typeof v.unit === 'string' ? ` ${v.unit.slice(0, 10)}` : '';
      const thr = typeof v.threshold === 'number' ? `, threshold ${fmtNum(v.threshold)}${unit}` : '';
      text += ` (${String(v.type || 'vital').slice(0, 20)} ${fmtNum(v.value)}${unit}${thr})`;
    }
    const ackAt = toMillis(d.acknowledgedAt);
    if (d.acknowledged === true) text += ackAt !== null ? `; acknowledged ${fmt(ackAt)}.` : '; acknowledged.';
    else text += '; NOT acknowledged.';
    return text;
  };
  if (inPeriod.length === 0) {
    items.push({
      text: 'No alerts or crisis events recorded in this period.',
      source: src('crisis_events', null, 'timestamp', period.toMs),
    });
  }
  for (const e of inPeriod.slice(0, MAX_LISTED_EVENTS)) {
    items.push({ text: describe(e), source: src('crisis_events', e.id, 'eventType', e.at) });
  }
  if (inPeriod.length > MAX_LISTED_EVENTS) {
    gaps.push(`${inPeriod.length} alerts in this period; only the ${MAX_LISTED_EVENTS} most recent are listed.`);
  }
  // Unacknowledged alerts are flagged even when older than the period.
  for (const e of sorted) {
    if (e.data.acknowledged === true) continue;
    flags.push({ text: `Unacknowledged: ${describe(e)}`, source: src('crisis_events', e.id, 'acknowledged', e.at) });
  }
  return { title: SECTION.alerts, items };
}

function rangeItem({ label, unit, rows, valueOf, fmt, collection, field }) {
  const vals = rows
    .map((r) => ({ id: r.id, at: r.at, v: valueOf(r) }))
    .filter((x) => typeof x.v === 'number' && Number.isFinite(x.v));
  if (vals.length === 0) return null;
  const nums = vals.map((x) => x.v);
  const mean = nums.reduce((a, b) => a + b, 0) / nums.length;
  const maxV = vals.reduce((a, b) => (b.v > a.v ? b : a));
  const minV = vals.reduce((a, b) => (b.v < a.v ? b : a));
  return {
    text: `${label}: ${vals.length} value${vals.length === 1 ? '' : 's'}, mean ${fmtNum(mean)}${unit}, ` +
      `lowest ${fmtNum(minV.v)}${unit} (${fmt(minV.at)}), highest ${fmtNum(maxV.v)}${unit} (${fmt(maxV.at)}).`,
    source: src(collection, maxV.id, field, maxV.at, { docIds: vals.slice(-50).map((x) => x.id) }),
  };
}

function buildVitals({ vitalsDaily, vitals, period, fmt, gaps, tz }) {
  const items = [];
  const daily = (vitalsDaily || [])
    .map((r) => ({ id: r.id, data: r.data || {}, at: dateKeyToMillis((r.data || {}).date, tz) }))
    .filter((r) => r.at !== null && r.at >= period.fromMs - DAY_MS && r.at <= period.toMs + DAY_MS)
    .sort((a, b) => a.at - b.at);
  if (daily.length > 0) {
    const defs = [
      { label: 'Heart rate, daily average', unit: ' bpm', field: 'hrAvg' },
      { label: 'Heart rate, daily resting estimate', unit: ' bpm', field: 'hrRestingEstimate' },
      { label: 'Heart rate, daily maximum', unit: ' bpm', field: 'hrMax' },
      { label: 'Sleep', unit: ' h', field: 'sleepHours' },
      { label: 'Steps per day', unit: '', field: 'steps' },
    ];
    for (const d of defs) {
      const it = rangeItem({
        label: d.label, unit: d.unit, rows: daily, valueOf: (r) => r.data[d.field], fmt,
        collection: 'vitals_daily', field: d.field,
      });
      if (it) items.push(it);
    }
  } else {
    const raw = (vitals || [])
      .map((r) => ({ id: r.id, data: r.data || {}, at: toMillis((r.data || {}).measuredAt) }))
      .filter((r) => r.at !== null && r.at >= period.fromMs && r.at <= period.toMs)
      .sort((a, b) => a.at - b.at);
    const defs = [
      { type: 'heart_rate', label: 'Heart rate readings', unit: ' bpm' },
      { type: 'sleep', label: 'Sleep readings', unit: ' h' },
      { type: 'steps', label: 'Step-count readings', unit: '' },
    ];
    for (const d of defs) {
      const it = rangeItem({
        label: d.label, unit: d.unit, rows: raw.filter((r) => r.data.type === d.type),
        valueOf: (r) => r.data.value, fmt, collection: 'vitals', field: 'value',
      });
      if (it) items.push(it);
    }
  }
  if (items.length === 0) gaps.push('No wearable vitals in this period.');
  return { title: SECTION.vitals, items };
}

function excerpt(text, maxChars) {
  const clean = String(text || '').replace(/\s+/g, ' ').trim();
  if (clean.length <= maxChars) return clean;
  return `${clean.slice(0, maxChars).trimEnd()}…`;
}

function buildJournal({ journals, period, fmt, gaps, excerptChars }) {
  const items = [];
  const list = (journals || [])
    .map((r) => ({ id: r.id, data: r.data || {}, at: toMillis((r.data || {}).createdAt) ?? toMillis((r.data || {}).clientCreatedAt) }))
    .filter((r) => r.at !== null && r.at >= period.fromMs && r.at <= period.toMs)
    .sort((a, b) => b.at - a.at);
  if (list.length === 0) {
    gaps.push('No journal entries shared with you in this period.');
    return { title: SECTION.journal, items };
  }
  for (const j of list.slice(0, MAX_LISTED_JOURNALS)) {
    const text = excerpt(j.data.text, excerptChars);
    const dur = isIntIn(j.data.durationSeconds, 1, 86400) ? `, ${Math.max(1, Math.round(j.data.durationSeconds / 60))} min voice note` : '';
    items.push({
      text: text ? `Journal (${fmt(j.at)}${dur}): "${text}"` : `Journal entry (${fmt(j.at)}${dur}) without a text note.`,
      source: src('journal_entries', j.id, 'text', j.at),
    });
  }
  if (list.length > MAX_LISTED_JOURNALS) {
    gaps.push(`${list.length} journal entries in this period; only the ${MAX_LISTED_JOURNALS} most recent are listed.`);
  }
  return { title: SECTION.journal, items };
}

function buildAppointments({ appointments, period, nowMs, fmt }) {
  const items = [];
  const list = (appointments || []).map((r) => {
    const d = r.data || {};
    return { id: r.id, d, at: toMillis(d.scheduledAt), proposed: toMillis(d.proposedAt) };
  });
  if (period.lastSessionId) {
    items.push({
      text: `Last completed session: ${fmt(period.lastSessionAtMs)}.`,
      source: src('appointments', period.lastSessionId, 'status', period.lastSessionAtMs),
    });
  } else {
    items.push({
      text: `No completed session on record; this brief covers the last ${DEFAULT_LOOKBACK_DAYS} days.`,
      source: src('appointments', null, 'status', nowMs),
    });
  }
  const upcoming = list
    .filter((a) => a.d.status === 'scheduled' && a.at !== null && a.at > nowMs)
    .sort((a, b) => a.at - b.at);
  if (upcoming.length) {
    const n = upcoming[0];
    items.push({
      text: `Next scheduled session: ${fmt(n.at)}${n.d.isVirtual === true ? ' (virtual)' : ''}.`,
      source: src('appointments', n.id, 'scheduledAt', n.at),
    });
  } else {
    items.push({ text: 'No upcoming scheduled session.', source: src('appointments', null, 'scheduledAt', nowMs) });
  }
  const other = list
    .filter((a) => ['cancelled', 'no_show', 'declined'].includes(a.d.status) && a.at !== null &&
      a.at >= period.fromMs && a.at <= period.toMs)
    .sort((a, b) => a.at - b.at);
  for (const a of other) {
    const label = a.d.status === 'no_show' ? 'marked no-show' : a.d.status;
    items.push({ text: `Session on ${fmt(a.at)} ${label}.`, source: src('appointments', a.id, 'status', a.at) });
  }
  const requested = list.filter((a) => a.d.status === 'requested');
  for (const a of requested) {
    items.push({
      text: a.proposed !== null ? `Open session request (proposed for ${fmt(a.proposed)}).` : 'Open session request (no proposed time).',
      source: src('appointments', a.id, 'status', a.proposed ?? toMillis(a.d.createdAt)),
    });
  }
  return { title: SECTION.appointments, items };
}

function buildAdherence({ logs, period, nowMs, tz, fmt, patient, gaps }) {
  const items = [];
  const firstDay = localDayIndex(period.fromMs, tz);
  const today = localDayIndex(nowMs, tz);
  const totalDays = Math.max(1, today - firstDay + 1);
  const days = new Set(logs.filter((l) => l.at >= period.fromMs && l.at <= nowMs).map((l) => localDayIndex(l.at, tz)));
  const latest = logs.length ? logs[logs.length - 1] : null;
  items.push({
    text: `Check-ins on ${days.size} of ${totalDays} days in this period.`,
    source: src('daily_logs', latest ? latest.id : null, 'timestamp', latest ? latest.at : nowMs),
  });

  const allDays = new Set(logs.map((l) => localDayIndex(l.at, tz)));
  let streakEnd = allDays.has(today) ? today : (allDays.has(today - 1) ? today - 1 : null);
  if (streakEnd !== null) {
    let n = 0;
    for (let d = streakEnd; allDays.has(d); d -= 1) n += 1;
    items.push({
      text: `Current consecutive check-in streak: ${pluralDays(n)} (from records read).`,
      source: src('daily_logs', latest.id, 'timestamp', latest.at),
    });
  } else {
    items.push({
      text: 'No check-in today or yesterday (current streak 0).',
      source: src('daily_logs', latest ? latest.id : null, 'timestamp', latest ? latest.at : nowMs),
    });
  }
  if (latest) {
    const since = today - localDayIndex(latest.at, tz);
    if (since >= 3) gaps.push(`No check-in in the last ${since} days (last on ${fmt(latest.at)}).`);
  }
  if (patient && isIntIn(patient.streak, 0, 100000)) {
    items.push({
      text: `Streak shown in the patient app: ${pluralDays(patient.streak)}.`,
      source: src('users', patient.__id || null, 'streak', toMillis(patient.lastCheckInAt)),
    });
  }
  return { title: SECTION.adherence, items };
}

// ------------------------------------------------------------------ main

/**
 * @param {object} input
 * @param {number} input.nowMs
 * @param {object} input.period from choosePeriod()
 * @param {number} [input.tzOffsetMinutes] patient/therapist local offset (minutes east of UTC)
 * @param {'absolute'|'relative'} [input.dateMode]
 * @param {number} [input.journalExcerptChars]
 * @param {object} [input.patient] users/{patientId} data (+ __id)
 * @param {{id: string, data: object}[]} input.assessments in-period clinical_assessments
 * @param {{id: string, data: object}[]} input.priorAssessments clinical_assessments before the period
 * @param {{id: string, data: object}[]} input.dailyLogs
 * @param {{id: string, data: object}[]} input.crisisEvents
 * @param {{id: string, data: object}[]} input.journalEntries
 * @param {{id: string, data: object}[]} input.vitalsDaily
 * @param {{id: string, data: object}[]} input.vitals raw readings (used only when vitalsDaily is empty)
 * @param {{id: string, data: object}[]} input.appointments
 * @param {string[]} [input.truncated] collections whose query hit its limit
 */
function buildSessionBrief(input) {
  const nowMs = input.nowMs;
  const period = input.period;
  const tz = clampTz(input.tzOffsetMinutes);
  const fmt = makeDateFormatter({ mode: input.dateMode || 'absolute', nowMs, tz });
  const flags = [];
  const gaps = [];

  const inPeriodRaw = (input.assessments || []).filter((r) => {
    const at = assessmentAt(r.data || {});
    return at !== null && at >= period.fromMs && at <= period.toMs;
  });
  const priorRaw = (input.priorAssessments || []).filter((r) => {
    const at = assessmentAt(r.data || {});
    return at !== null && at < period.fromMs;
  });
  const inPeriod = extractInstruments(inPeriodRaw);
  const prior = extractInstruments(priorRaw);
  if (inPeriod.invalid > 0) gaps.push(`${inPeriod.invalid} assessment record(s) with missing or out-of-range values were skipped.`);

  const logs = (input.dailyLogs || [])
    .map((r) => ({ id: r.id, data: r.data || {}, at: toMillis((r.data || {}).timestamp) ?? toMillis((r.data || {}).clientCreatedAt) }))
    .filter((l) => l.at !== null && l.at <= nowMs)
    .sort((a, b) => a.at - b.at);
  const events = (input.crisisEvents || [])
    .map((r) => ({ id: r.id, data: r.data || {}, at: toMillis((r.data || {}).timestamp) }))
    .filter((e) => e.at !== null);

  const sections = [
    buildInstruments({ inPeriod, prior, fmt, nowMs, flags, gaps }),
    buildCheckins({ logs, period, fmt, flags, gaps }),
    buildAlerts({ events, period, fmt, flags, gaps }),
    buildVitals({ vitalsDaily: input.vitalsDaily, vitals: input.vitals, period, fmt, gaps, tz }),
    buildJournal({
      journals: input.journalEntries, period, fmt, gaps,
      excerptChars: input.journalExcerptChars || DEFAULT_JOURNAL_EXCERPT_CHARS,
    }),
    buildAppointments({ appointments: input.appointments, period, nowMs, fmt }),
    buildAdherence({ logs, period, nowMs, tz, fmt, patient: input.patient, gaps }),
  ];

  if (period.capped) gaps.push(`The last completed session was more than ${MAX_LOOKBACK_DAYS} days ago; this brief covers only the last ${MAX_LOOKBACK_DAYS} days.`);
  for (const c of input.truncated || []) {
    gaps.push(`Only the most recent ${c} records allowed by the read limit were used; older records in this period may be missing.`);
  }

  // Same statement may be raised twice (e.g. item 9 flagged in both lists): dedupe flags by text.
  const seen = new Set();
  const uniqueFlags = flags.filter((f) => (seen.has(f.text) ? false : (seen.add(f.text), true)));

  return {
    generatedAt: new Date(nowMs).toISOString(),
    period: {
      from: new Date(period.fromMs).toISOString(),
      to: new Date(period.toMs).toISOString(),
      basis: period.basis,
      days: Math.max(1, Math.round((period.toMs - period.fromMs) / DAY_MS)),
    },
    sections,
    flags: uniqueFlags,
    dataGaps: gaps,
  };
}

module.exports = {
  buildSessionBrief,
  choosePeriod,
  toMillis,
  localDateKey,
  makeDateFormatter,
  phq9Band,
  gad7Band,
  DAY_MS,
  DEFAULT_LOOKBACK_DAYS,
  MAX_LOOKBACK_DAYS,
  SECTION,
};
