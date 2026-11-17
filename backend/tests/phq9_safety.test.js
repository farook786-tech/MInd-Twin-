/**
 * PHQ-9 safety tests: exhaustive scoring/banding, item-9 safety flow,
 * strict input validation, and item 9 in clinical risk factors.
 */
const ClinicalService = require('../src/services/ClinicalService');

const svc = Object.create(ClinicalService.prototype);
const score = (r) => ClinicalService.prototype.scorePHQ9.call(svc, r);

function band(total) {
  if (total >= 20) return 'severe';
  if (total >= 15) return 'moderately_severe';
  if (total >= 10) return 'moderate';
  if (total >= 5) return 'mild';
  return 'minimal';
}

describe('PHQ-9 scoring: exhaustive over all 4^9 = 262,144 answer patterns', () => {
  test('sum, severity band and item-9 flag are correct for every pattern', () => {
    const r = new Array(9).fill(0);
    let checked = 0;
    let errors = 0;
    for (let code = 0; code < 4 ** 9; code++) {
      let c = code;
      let total = 0;
      for (let i = 0; i < 9; i++) { r[i] = c % 4; c = Math.floor(c / 4); total += r[i]; }
      const out = score(r);
      if (out.score !== total || out.severity !== band(total) ||
          out.suicidalIdeation !== (r[8] > 0) || out.requiresSafetyAssessment !== (r[8] > 0) || out.item9 !== r[8]) {
        errors++;
      }
      checked++;
    }
    expect(checked).toBe(262144);
    expect(errors).toBe(0);
  });

  test('item 9 > 0 flags safety even when the total is minimal', () => {
    const out = score([0, 0, 0, 0, 0, 0, 0, 0, 1]);
    expect(out.score).toBe(1);
    expect(out.severity).toBe('minimal');
    expect(out.suicidalIdeation).toBe(true);
  });

  test('numeric strings are accepted', () => {
    expect(score(['3', '3', '3', '3', '3', '3', '3', '3', '3']).score).toBe(27);
  });

  test.each([
    [[0, 0, 0, 0, 0, 0, 0, 0, 2.7]],
    [[0, 0, 0, 0, 0, 0, 0, 0, '3abc']],
    [[0, 0, 0, 0, 0, 0, 0, 0, null]],
    [[0, 0, 0, 0, 0, 0, 0, 0, true]],
    [[0, 0, 0, 0, 0, 0, 0, 0, '']],
    [[0, 0, 0, 0, 0, 0, 0, 0, -1]],
    [[0, 0, 0, 0, 0, 0, 0, 0, 4]],
    [[0, 0, 0, 0, 0, 0, 0, 0, NaN]],
    [[0, 0, 0, 0, 0, 0, 0, 0]],
    [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]],
    ['000000000'],
    [null],
  ])('rejects invalid responses %p', (responses) => {
    expect(() => score(responses)).toThrow();
  });
});

function fakeDb(rows = {}) {
  const runs = [];
  return {
    runs,
    prepare(sql) {
      return {
        get: () => {
          if (/COUNT\(\*\) as count FROM phq9_assessments/.test(sql)) return { count: rows.phq9Count ?? 1 };
          if (/FROM clinical_alerts/.test(sql)) return undefined;
          if (/FROM shared_checkins/.test(sql) && /AVG/.test(sql)) return rows.checks ?? { avg_mood: null, avg_anxiety: null, avg_sleep: null, avg_hr: null, check_count: 0 };
          if (/FROM shared_checkins/.test(sql)) return rows.lastCheck ?? { created_at: new Date().toISOString() };
          if (/FROM shared_appointments/.test(sql)) return { count: 0 };
          if (/FROM phq9_assessments/.test(sql)) return rows.latestPHQ9;
          if (/FROM patients/.test(sql)) return { therapist_id: 't1' };
          return undefined;
        },
        run: (...args) => { runs.push({ sql, args }); return {}; },
        all: () => [],
      };
    },
  };
}

function serviceWith(db) {
  const s = new ClinicalService();
  Object.defineProperty(s, 'db', { get: () => db });
  s.calculateTreatmentResponse = jest.fn().mockResolvedValue({});
  jest.spyOn(console, 'log').mockImplementation(() => {});
  return s;
}

describe('createPHQ9Assessment item-9 safety flow', () => {
  test('item 9 = 1 with total 1 creates a CRITICAL item-9 alert', async () => {
    const db = fakeDb();
    const s = serviceWith(db);
    const alert = jest.spyOn(s, 'createClinicalAlert');
    const res = await s.createPHQ9Assessment('p1', 't1', [0, 0, 0, 0, 0, 0, 0, 0, 1]);
    expect(res.suicidalIdeation).toBe(true);
    expect(res.requiresSafetyAssessment).toBe(true);
    expect(alert).toHaveBeenCalledWith('p1', 't1', 'PHQ9_ITEM9_SUICIDAL_IDEATION', 'critical', expect.any(String), 1);
  });

  test('item 9 = 0 with total 14 creates no item-9 alert', async () => {
    const s = serviceWith(fakeDb());
    const alert = jest.spyOn(s, 'createClinicalAlert');
    await s.createPHQ9Assessment('p1', 't1', [2, 2, 2, 2, 2, 2, 1, 1, 0]);
    expect(alert).not.toHaveBeenCalled();
  });

  test('item 9 = 3 and total 27 raises both item-9 and high-score alerts', async () => {
    const s = serviceWith(fakeDb());
    const alert = jest.spyOn(s, 'createClinicalAlert');
    await s.createPHQ9Assessment('p1', 't1', new Array(9).fill(3));
    const types = alert.mock.calls.map((c) => c[2]);
    expect(types).toEqual(expect.arrayContaining(['PHQ9_ITEM9_SUICIDAL_IDEATION', 'HIGH_PHQ9_SCORE']));
  });

  test('invalid responses reject (no assessment stored)', async () => {
    const db = fakeDb();
    const s = serviceWith(db);
    await expect(s.createPHQ9Assessment('p1', 't1', [0, 0, 0, 0, 0, 0, 0, 0, '1x'])).rejects.toThrow();
    expect(db.runs.length).toBe(0);
  });
});

describe('calculateClinicalRiskFactors uses PHQ-9 item 9', () => {
  test('latest PHQ-9 with item 9 > 0 forces at least HIGH risk', async () => {
    const s = serviceWith(fakeDb({ latestPHQ9: { score: 3, responses: JSON.stringify([0, 0, 1, 0, 0, 0, 0, 0, 2]) } }));
    jest.spyOn(s, 'createClinicalAlert').mockResolvedValue({});
    const out = await s.calculateClinicalRiskFactors('p1');
    expect(out.riskFactors).toContain('phq9_item9_suicidal_ideation');
    expect(['high', 'critical']).toContain(out.riskLevel);
  });

  test('monotonic: adding a worse PHQ-9 never lowers severity', async () => {
    const base = await serviceWith(fakeDb({ latestPHQ9: { score: 4, responses: '[0,0,0,0,0,0,1,1,2]' } })).calculateClinicalRiskFactors('p1');
    const worse = await serviceWith(fakeDb({ latestPHQ9: { score: 22, responses: '[3,3,3,3,3,3,1,1,2]' } })).calculateClinicalRiskFactors('p1');
    expect(worse.severity).toBeGreaterThanOrEqual(base.severity);
  });

  test('no PHQ-9 and no data does not crash and is not fabricated as high', async () => {
    const s = serviceWith(fakeDb({ latestPHQ9: undefined }));
    const out = await s.calculateClinicalRiskFactors('p1');
    expect(out.riskLevel).toBe('low');
  });
});
