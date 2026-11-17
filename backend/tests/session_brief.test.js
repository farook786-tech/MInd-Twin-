'use strict';

/**
 * Pre-session brief: deterministic builder (fixtures), de-identification,
 * narrative gate + post-validation, and the route's access control.
 */

const express = require('express');
const {
  buildSessionBrief, choosePeriod, DAY_MS,
} = require('../src/services/SessionBriefBuilder');
const {
  generateNarrative, deidentifyBrief, validateNarrative, scrubText, narrativeGate,
} = require('../src/services/SessionBriefNarrative');
const { createSessionBriefRouter } = require('../src/routes/sessionBrief');

// 2026-11-17T12:00:00Z
const NOW = Date.UTC(2026, 10, 17, 12, 0, 0);
const at = (y, mo, d, h = 10) => new Date(Date.UTC(y, mo - 1, d, h));
const daysAgo = (n, h = 10) => new Date(NOW - n * DAY_MS + (h - 12) * 3600 * 1000);

const PATIENT = {
  name: 'Asha Verma',
  email: 'asha.verma@example.com',
  phone: '+91 98765 43210',
  role: 'patient',
  therapistId: 'ther1',
  streak: 4,
  settings: { aiSummaryConsent: true },
};

function fixture(overrides = {}) {
  const appointments = [
    { id: 'apptDone', data: { patientId: 'p1', therapistId: 'ther1', status: 'completed', scheduledAt: at(2026, 11, 1, 9) } },
    { id: 'apptOld', data: { patientId: 'p1', therapistId: 'ther1', status: 'completed', scheduledAt: at(2026, 10, 1, 9) } },
    { id: 'apptNext', data: { patientId: 'p1', therapistId: 'ther1', status: 'scheduled', scheduledAt: at(2026, 11, 20, 9), isVirtual: true } },
    { id: 'apptNoShow', data: { patientId: 'p1', therapistId: 'ther1', status: 'no_show', scheduledAt: at(2026, 11, 8, 9) } },
  ];
  const period = choosePeriod({ nowMs: NOW, appointments, therapistId: 'ther1' });
  return {
    nowMs: NOW,
    period,
    tzOffsetMinutes: 0,
    patient: { ...PATIENT, __id: 'p1' },
    appointments,
    priorAssessments: [
      { id: 'phqPrior', data: { type: 'phq9_gad7', totalScore: 9, item9: 0, gad7Score: 8, timestamp: at(2026, 10, 25) } },
    ],
    assessments: [
      { id: 'phqA', data: { type: 'phq9_gad7', totalScore: 11, item9: 0, gad7Score: 9, timestamp: at(2026, 11, 2) } },
      { id: 'phqB', data: { type: 'phq9_gad7', totalScore: 17, item9: 1, gad7Score: 12, timestamp: at(2026, 11, 15) } },
      { id: 'cssrs1', data: { type: 'cssrs', cssrsRisk: 'moderate', cssrsAnswers: { q1: true, q2: true, q3: true, q4: false, q5: false, q6: false, q6Recent: null }, timestamp: at(2026, 11, 15, 11) } },
    ],
    dailyLogs: [
      { id: 'log1', data: { moodScore: 4, sleepScore: 3, riskScore: 40, timestamp: at(2026, 11, 3) } },
      { id: 'log2', data: { moodScore: 4, sleepScore: 3, riskScore: 45, timestamp: at(2026, 11, 6) } },
      { id: 'log3', data: { moodScore: 2, sleepScore: 2, riskScore: 70, timestamp: at(2026, 11, 15) } },
      { id: 'log4', data: { moodScore: 2, sleepScore: 1, riskScore: 80, timestamp: at(2026, 11, 16) } },
      { id: 'log5', data: { moodScore: 1, sleepScore: 1, riskScore: 78, timestamp: at(2026, 11, 17, 8) } },
    ],
    crisisEvents: [
      { id: 'ev1', data: { eventType: 'cssrs_moderate', severity: 'medium', acknowledged: false, timestamp: at(2026, 11, 15, 11), patientName: 'Asha Verma' } },
      { id: 'ev2', data: { eventType: 'vital_high', severity: 'high', acknowledged: true, acknowledgedAt: at(2026, 11, 10, 13), vital: { type: 'heart_rate', value: 132, unit: 'bpm', threshold: 120 }, timestamp: at(2026, 11, 10, 12) } },
      { id: 'evOld', data: { eventType: 'sos', severity: 'critical', acknowledged: true, timestamp: at(2026, 10, 1) } },
    ],
    journalEntries: [
      { id: 'j1', data: { text: 'Could not sleep again. Call me on 98765 43210 or mail asha.verma@example.com, I live at 12 MG Road.', durationSeconds: 95, createdAt: at(2026, 11, 14) } },
      { id: 'jOld', data: { text: 'old entry', createdAt: at(2026, 10, 20) } },
    ],
    vitalsDaily: [
      { id: 'p1_2026-11-15', data: { date: '2026-11-15', hrAvg: 82, hrMax: 140, sleepHours: 4.5, steps: 3000 } },
      { id: 'p1_2026-11-16', data: { date: '2026-11-16', hrAvg: 88, hrMax: 151, sleepHours: 3.5, steps: 2100 } },
    ],
    vitals: [],
    truncated: [],
    ...overrides,
  };
}

const allItems = (brief) => brief.sections.flatMap((s) => s.items);
const section = (brief, prefix) => brief.sections.find((s) => s.title.startsWith(prefix));

describe('choosePeriod', () => {
  test('uses the last completed session with this therapist', () => {
    const p = fixture().period;
    expect(p.basis).toBe('last_completed_session');
    expect(p.lastSessionId).toBe('apptDone');
    expect(p.fromMs).toBe(at(2026, 11, 1, 9).getTime());
  });

  test('falls back to 14 days; ignores future and other-therapist sessions; caps at 90 days', () => {
    const p = choosePeriod({
      nowMs: NOW,
      therapistId: 'ther1',
      appointments: [
        { id: 'f', data: { status: 'completed', therapistId: 'ther1', scheduledAt: at(2026, 11, 30) } },
        { id: 'o', data: { status: 'completed', therapistId: 'other', scheduledAt: at(2026, 11, 10) } },
        { id: 's', data: { status: 'scheduled', therapistId: 'ther1', scheduledAt: at(2026, 11, 10) } },
      ],
    });
    expect(p.basis).toBe('default_14_days');
    expect(p.fromMs).toBe(NOW - 14 * DAY_MS);

    const capped = choosePeriod({
      nowMs: NOW, therapistId: 'ther1',
      appointments: [{ id: 'a', data: { status: 'completed', therapistId: 'ther1', scheduledAt: at(2026, 1, 1) } }],
    });
    expect(capped.capped).toBe(true);
    expect(capped.fromMs).toBe(NOW - 90 * DAY_MS);
  });
});

describe('buildSessionBrief (deterministic)', () => {
  const brief = buildSessionBrief(fixture());

  test('top-level shape', () => {
    expect(brief.generatedAt).toBe(new Date(NOW).toISOString());
    expect(brief.period.from).toBe(at(2026, 11, 1, 9).toISOString());
    expect(brief.period.basis).toBe('last_completed_session');
    expect(brief.sections.map((s) => s.title)).toEqual([
      'Instruments (PHQ-9, GAD-7, C-SSRS)', 'Daily check-ins', 'Alerts and crisis events',
      'Vitals (wearable)', 'Journal entries shared with you', 'Appointments', 'Adherence',
    ]);
    expect(Array.isArray(brief.flags)).toBe(true);
    expect(Array.isArray(brief.dataGaps)).toBe(true);
  });

  test('every item and flag carries a source', () => {
    for (const it of [...allItems(brief), ...brief.flags]) {
      expect(typeof it.text).toBe('string');
      expect(it.source).toEqual(expect.objectContaining({ collection: expect.any(String) }));
      expect('docId' in it.source && 'field' in it.source && 'at' in it.source).toBe(true);
    }
  });

  test('instrument scores and neutral change wording with dates', () => {
    const texts = section(brief, 'Instruments').items.map((i) => i.text);
    expect(texts).toContain('PHQ-9 = 11 (moderate) on Nov 2.');
    expect(texts).toContain('PHQ-9 = 17 (moderately severe) on Nov 15.');
    // Baseline = last result before the period.
    expect(texts).toContain('PHQ-9 rose from 9 to 17 (Oct 25 → Nov 15).');
    expect(texts).toContain('GAD-7 rose from 8 to 12 (Oct 25 → Nov 15).');
    expect(texts.some((t) => t.startsWith('C-SSRS screener on Nov 15: risk moderate; Q1 = yes'))).toBe(true);
    const change = section(brief, 'Instruments').items.find((i) => i.text.startsWith('PHQ-9 rose'));
    expect(change.source).toEqual({ collection: 'clinical_assessments', docId: 'phqB', field: 'totalScore', at: at(2026, 11, 15).toISOString() });
    expect(change.comparedWith.docId).toBe('phqPrior');
  });

  test('change within the period when no prior result exists', () => {
    const b = buildSessionBrief(fixture({ priorAssessments: [] }));
    expect(allItems(b).map((i) => i.text)).toContain('PHQ-9 rose from 11 to 17 (Nov 2 → Nov 15).');
  });

  test('flags: item 9, C-SSRS moderate, unacknowledged alert, indicator >= 75', () => {
    const f = brief.flags.map((x) => x.text);
    expect(f).toContain('PHQ-9 item 9 (thoughts of death or self-harm) = 1 on Nov 15.');
    expect(f.some((t) => t.startsWith('C-SSRS screener on Nov 15: risk moderate'))).toBe(true);
    expect(f.some((t) => t.startsWith('Unacknowledged: C-SSRS moderate-risk alert, severity medium, on Nov 15'))).toBe(true);
    expect(f.some((t) => t.startsWith('Check-in wellbeing indicator 80 on Nov 16'))).toBe(true);
    expect(f.some((t) => t.includes('vital'))).toBe(false); // acknowledged
    expect(new Set(f).size).toBe(f.length);
  });

  test('alerts list acknowledgement; old events outside the period are not listed', () => {
    const texts = section(brief, 'Alerts').items.map((i) => i.text);
    expect(texts).toContain('Vital above threshold, severity high, on Nov 10 (heart_rate 132 bpm, threshold 120 bpm); acknowledged Nov 10.');
    expect(texts.some((t) => t.includes('SOS'))).toBe(false);
    expect(texts.join(' ')).not.toContain('Asha');
  });

  test('check-in statistics', () => {
    const texts = section(brief, 'Daily check-ins').items.map((i) => i.text);
    expect(texts[0]).toBe('5 check-ins between Nov 3 and Nov 17.');
    expect(texts).toContain('Mood score: 5 values, mean 2.6, range 1-4; latest 1 on Nov 17; mean of earlier half 4, later half 1.7.');
  });

  test('vitals from vitals_daily', () => {
    const texts = section(brief, 'Vitals').items.map((i) => i.text);
    expect(texts).toContain('Heart rate, daily average: 2 values, mean 85 bpm, lowest 82 bpm (Nov 15), highest 88 bpm (Nov 16).');
    expect(texts).toContain('Sleep: 2 values, mean 4 h, lowest 3.5 h (Nov 16), highest 4.5 h (Nov 15).');
    expect(section(brief, 'Vitals').items[0].source.collection).toBe('vitals_daily');
  });

  test('raw vitals fallback when no vitals_daily docs', () => {
    const b = buildSessionBrief(fixture({
      vitalsDaily: [],
      vitals: [
        { id: 'v1', data: { type: 'heart_rate', value: 70, measuredAt: at(2026, 11, 12) } },
        { id: 'v2', data: { type: 'heart_rate', value: 90, measuredAt: at(2026, 11, 13) } },
      ],
    }));
    const it = section(b, 'Vitals').items[0];
    expect(it.text).toBe('Heart rate readings: 2 values, mean 80 bpm, lowest 70 bpm (Nov 12), highest 90 bpm (Nov 13).');
    expect(it.source).toEqual(expect.objectContaining({ collection: 'vitals', docId: 'v2', field: 'value' }));
    const none = buildSessionBrief(fixture({ vitalsDaily: [], vitals: [] }));
    expect(none.dataGaps).toContain('No wearable vitals in this period.');
  });

  test('journal excerpts (in period only, truncated)', () => {
    const items = section(brief, 'Journal').items;
    expect(items).toHaveLength(1);
    expect(items[0].text.startsWith('Journal (Nov 14, 2 min voice note): "Could not sleep again.')).toBe(true);
    const short = buildSessionBrief({ ...fixture(), journalExcerptChars: 20 });
    expect(section(short, 'Journal').items[0].text).toBe('Journal (Nov 14, 2 min voice note): "Could not sleep agai…"');
  });

  test('appointments and adherence', () => {
    const appts = section(brief, 'Appointments').items.map((i) => i.text);
    expect(appts).toEqual([
      'Last completed session: Nov 1.',
      'Next scheduled session: Nov 20 (virtual).',
      'Session on Nov 8 marked no-show.',
    ]);
    const adh = section(brief, 'Adherence').items.map((i) => i.text);
    expect(adh).toContain('Check-ins on 5 of 17 days in this period.');
    expect(adh).toContain('Current consecutive check-in streak: 3 days (from records read).');
    expect(adh).toContain('Streak shown in the patient app: 4 days.');
  });

  test('data gaps for missing instruments and stale data; never fabricates', () => {
    const b = buildSessionBrief(fixture({ assessments: [], priorAssessments: [], dailyLogs: [], journalEntries: [], truncated: ['daily_logs'] }));
    expect(b.dataGaps).toEqual(expect.arrayContaining([
      'No PHQ-9 completed in this period.', 'No PHQ-9 on record.', 'No GAD-7 completed in this period.',
      'No C-SSRS screener completed in this period.', 'No daily check-ins in this period.',
      'No journal entries shared with you in this period.',
    ]));
    expect(b.dataGaps.some((g) => g.includes('daily_logs records allowed by the read limit'))).toBe(true);
    const stale = buildSessionBrief(fixture({ assessments: [], priorAssessments: [
      { id: 'old', data: { type: 'phq9_gad7', totalScore: 5, timestamp: at(2026, 10, 1) } },
    ] }));
    expect(stale.dataGaps).toContain('Latest PHQ-9 is 47 days old (older than the 14-day recency window).');
    expect(allItems(stale).map((i) => i.text)).toContain('Most recent PHQ-9 before this period: 5 (mild) on Oct 1.');
  });

  test('skips out-of-range scores instead of showing them', () => {
    const b = buildSessionBrief(fixture({ assessments: [{ id: 'bad', data: { type: 'phq9_gad7', totalScore: 40, timestamp: at(2026, 11, 5) } }] }));
    expect(section(b, 'Instruments').items.some((i) => i.text.includes('40'))).toBe(false);
    expect(b.dataGaps.some((g) => g.includes('skipped'))).toBe(true);
  });

  test('no treatment or medication language anywhere', () => {
    const all = JSON.stringify(brief).toLowerCase();
    for (const w of ['medication', 'dose', 'prescri', 'recommend', 'diagnosis', 'diagnosed', 'should ']) expect(all).not.toContain(w);
  });

  test('relative date mode', () => {
    const rel = buildSessionBrief({ ...fixture(), dateMode: 'relative' });
    const texts = allItems(rel).map((i) => i.text);
    expect(texts).toContain('PHQ-9 rose from 9 to 17 (23 days ago → 2 days ago).');
    expect(texts).toContain('Next scheduled session: in 3 days (virtual).');
  });
});

describe('de-identification', () => {
  const rel = buildSessionBrief({ ...fixture(), dateMode: 'relative', journalExcerptChars: 80 });
  const deid = deidentifyBrief(rel, PATIENT);
  const json = JSON.stringify(deid);

  test('removes names, contact details, ids, sources and calendar dates', () => {
    expect(json).not.toMatch(/Asha|Verma|example\.com|98765|43210|MG Road/i);
    expect(json).not.toMatch(/p1_|phqB|apptDone|ther1|docId|source/);
    expect(json).not.toMatch(/Nov|Oct|2026/);
    expect(json).toContain('days ago');
    expect(deid.periodLengthDays).toBe(16);
  });

  test('scrubText patterns', () => {
    expect(scrubText('ring +91 98765-43210 now')).toBe('ring [number removed] now');
    expect(scrubText('mail a.b@c.io')).toBe('mail [email removed]');
    expect(scrubText('flat at 221B Baker Street')).toContain('[address removed]');
    expect(scrubText('see https://x.y/z')).toBe('see [link removed]');
    expect(scrubText('Ravi said hi', { names: ['Ravi'] })).toBe('the patient said hi');
    // Structured statistics are not mangled outside free text.
    expect(scrubText('mean 12345 (3 days ago)', { freeText: false })).toBe('mean 12345 (3 days ago)');
  });
});

describe('narrative', () => {
  const rel = buildSessionBrief({ ...fixture(), dateMode: 'relative', journalExcerptChars: 80 });
  const ON = { AI_BRIEF_LLM_ENABLED: 'true' };

  test('gate: server flag and patient consent are both required', () => {
    expect(narrativeGate({}, PATIENT)).toEqual({ enabled: false, reason: 'disabled_on_server' });
    expect(narrativeGate(ON, { ...PATIENT, settings: {} })).toEqual({ enabled: false, reason: 'no_patient_consent' });
    expect(narrativeGate(ON, { ...PATIENT, settings: { aiSummaryConsent: 'yes' } }).enabled).toBe(false);
    expect(narrativeGate(ON, PATIENT).enabled).toBe(true);
  });

  test('no provider call without consent', async () => {
    const callLlm = jest.fn();
    const out = await generateNarrative({ relativeBrief: rel, patient: { ...PATIENT, settings: {} }, env: ON, callLlm });
    expect(out).toEqual({ narrative: null, reason: 'no_patient_consent' });
    expect(callLlm).not.toHaveBeenCalled();
  });

  test('sends only de-identified JSON and accepts a grounded narrative', async () => {
    const callLlm = jest.fn(async () =>
      'PHQ-9 rose from 9 to 17 over the period, with item 9 = 1 two days ago. A C-SSRS moderate-risk alert is not acknowledged.');
    const out = await generateNarrative({ relativeBrief: rel, patient: PATIENT, env: ON, callLlm });
    expect(out.reason).toBeNull();
    expect(out.narrative).toMatch(/^PHQ-9 rose/);
    const { system, user } = callLlm.mock.calls[0][0];
    expect(system).toMatch(/Never mention, suggest or adjust any medication/);
    expect(user).not.toMatch(/Asha|example\.com|98765|Nov|p1/);
    expect(JSON.parse(user).sections.length).toBeGreaterThan(0);
  });

  test.each([
    ['Consider starting sertraline 50 mg.', 'rejected_mentions_medication'],
    ['The patient may need a dose change.', 'rejected_mentions_medication'],
    ['Findings are consistent with major depressive disorder.', 'rejected_mentions_diagnosis'],
    ['PHQ-9 rose from 9 to 99.', 'rejected_number_not_in_input'],
    ['We recommend weekly sessions.', 'rejected_gives_advice'],
    [Array(160).fill('word').join(' '), 'rejected_too_long'],
  ])('rejects unsafe output: %s', async (text, reason) => {
    const out = await generateNarrative({ relativeBrief: rel, patient: PATIENT, env: ON, callLlm: async () => text });
    expect(out).toEqual({ narrative: null, reason });
  });

  test('provider failure falls back to deterministic only', async () => {
    const out = await generateNarrative({ relativeBrief: rel, patient: PATIENT, env: ON, callLlm: async () => { throw new Error('x'); } });
    expect(out).toEqual({ narrative: null, reason: 'provider_unavailable' });
  });

  test('validateNarrative allows numbers present in input only', () => {
    expect(validateNarrative('Score 17.', { a: 'x 17' }).ok).toBe(true);
    expect(validateNarrative('Score 18.', { a: 'x 17' }).ok).toBe(false);
  });
});

describe('POST /api/brief/:patientId', () => {
  let server;
  let base;
  const users = { p1: PATIENT, p2: { ...PATIENT, therapistId: 'someoneElse' } };
  const verifyIdToken = jest.fn(async (token, checkRevoked) => {
    if (checkRevoked !== true) throw new Error('checkRevoked must be true');
    if (token === 'ther') return { uid: 'ther1', role: 'therapist' };
    if (token === 'pending') return { uid: 'ther1', role: 'therapist_pending' };
    if (token === 'patient') return { uid: 'p1', role: 'patient' };
    const e = new Error('expired');
    e.code = 'auth/id-token-expired';
    throw e;
  });
  const loadData = jest.fn(async ({ nowMs }) => {
    const f = fixture();
    return { ...f, period: choosePeriod({ nowMs, appointments: f.appointments, therapistId: 'ther1' }) };
  });

  beforeAll(async () => {
    const app = express();
    app.use(express.json());
    app.use('/api/brief', createSessionBriefRouter({
      getAuth: () => ({ verifyIdToken }),
      readPatient: async (id) => users[id] || null,
      loadData,
      env: {},
      now: () => NOW,
      perUid: { capacity: 3, windowMs: 60 * 60 * 1000 },
    }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', () => {
        base = `http://127.0.0.1:${server.address().port}/api/brief`;
        resolve();
      });
    });
  });
  afterAll(() => new Promise((r) => server.close(r)));

  const post = async (id, token) => {
    const headers = { 'content-type': 'application/json' };
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await fetch(`${base}/${id}`, { method: 'POST', headers, body: '{"tzOffsetMinutes":0}' });
    return { status: res.status, json: await res.json() };
  };

  test('401 without or with an expired token', async () => {
    expect((await post('p1')).status).toBe(401);
    expect((await post('p1', 'bad')).json.error.code).toBe('unauthenticated');
  });

  test('403 for non-therapist roles and for other therapists\' or unknown patients', async () => {
    expect((await post('p1', 'patient')).status).toBe(403);
    expect((await post('p1', 'pending')).status).toBe(403);
    expect((await post('p2', 'ther')).status).toBe(403);
    expect((await post('nobody', 'ther')).status).toBe(403);
    expect(loadData).not.toHaveBeenCalled();
  });

  test('200 with deterministic brief; narrative null when disabled', async () => {
    const { status, json } = await post('p1', 'ther');
    expect(status).toBe(200);
    expect(json.brief.sections).toHaveLength(7);
    expect(json.narrative).toBeNull();
    expect(json.narrativeReason).toBe('disabled_on_server');
    expect(loadData).toHaveBeenCalledWith(expect.objectContaining({ patientId: 'p1', therapistId: 'ther1' }));
  });

  test('per-uid rate limit', async () => {
    // capacity 3: 1 used above (403s on p2/nobody also count) -> eventually 429.
    let last;
    for (let i = 0; i < 4; i += 1) last = await post('p1', 'ther');
    expect(last.status).toBe(429);
    expect(last.json.error.code).toBe('resource-exhausted');
  });
});
