/**
 * Clinical-safety tests for the crisis decision layer in src/routes/ml.js.
 * Eval sets + lexicon live in ../ml_service (single source of truth).
 * Report: docs/ML_SAFETY_EVALUATION.md
 */
const fs = require('fs');
const path = require('path');

jest.mock('axios', () => ({ post: jest.fn() }));
jest.mock('../src/middleware/auth', () => ({
  authMiddleware: (req, res, next) => next(),
  canAccessPatient: () => true,
}));
jest.mock('../src/middleware/TokenBucketMiddleware', () => () => (req, res, next) => next());
jest.mock('../src/database/Database', () => ({ getInstance: () => ({ getDB: () => null }) }));

const axios = require('axios');

beforeAll(() => jest.spyOn(console, 'warn').mockImplementation(() => {}));
const ml = require('../src/routes/ml');

const { evaluateCrisis, normalizeText, readModelProbability, CRISIS_LEXICON } = ml;
const ML_DIR = path.join(__dirname, '..', '..', 'ml_service');
const EVAL_FILES = ['crisis_eval_set.jsonl', 'crisis_challenge_set.jsonl', 'crisis_blind_set.jsonl'];
const SI_CATEGORIES = new Set([
  'explicit_si', 'passive_si', 'self_harm', 'method_plan', 'negated_si', 'slang_si', 'hinglish_si',
]);

function loadSet(file) {
  return fs
    .readFileSync(path.join(ML_DIR, 'eval', file), 'utf8')
    .split(/\r?\n/)
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l));
}

describe('lexicon copy is in sync with ml_service/crisis_lexicon.json', () => {
  test('embedded CRISIS_LEXICON equals the source of truth', () => {
    const src = JSON.parse(fs.readFileSync(path.join(ML_DIR, 'crisis_lexicon.json'), 'utf8'));
    expect(CRISIS_LEXICON.version).toBe(src.version);
    expect(CRISIS_LEXICON.model_threshold).toBe(src.model_threshold);
    expect(CRISIS_LEXICON.negation_cues).toBe(src.negation_cues);
    expect(CRISIS_LEXICON.extra_separators).toBe(src.extra_separators);
    const strip = (arr, cat = true) => arr.map((e) => (cat ? { id: e.id, cat: e.cat, re: e.re } : { id: e.id, re: e.re }));
    expect(CRISIS_LEXICON.hard).toEqual(strip(src.hard));
    expect(CRISIS_LEXICON.soft).toEqual(strip(src.soft));
    expect(CRISIS_LEXICON.idiom).toEqual(strip(src.idiom, false));
  });
});

describe('normalization', () => {
  test.each([
    ["I DON'T want to live", 'i dont want to live'],
    ['Want. To. Die.', 'want to die'],
    ['i’m   suicidal!!!', 'im suicidal'],
    ['जीने का मन नहीं है।', 'जीने का मन नहीं है'],
    ['', ''],
  ])('%s', (input, expected) => {
    expect(normalizeText(input)).toBe(expected);
  });
  test('non-string input is safe', () => {
    expect(normalizeText(null)).toBe('');
    expect(normalizeText(undefined)).toBe('');
    expect(evaluateCrisis(undefined, null).escalate).toBe(false);
  });
});

describe.each(EVAL_FILES)('rule layer alone (model DOWN) on %s', (file) => {
  const items = loadSet(file);
  const results = items.map((it) => ({ ...it, d: evaluateCrisis(it.t, null) }));

  test('recall on every crisis-labelled item is 100% (no false negatives)', () => {
    const fns = results.filter((r) => r.y === 1 && !r.d.escalate).map((r) => `[${r.c}] ${r.t}`);
    expect(fns).toEqual([]);
  });

  test('explicit + passive ideation always hit a HARD phrase (severity >= high)', () => {
    const weak = results
      .filter((r) => (r.c === 'explicit_si' || r.c === 'passive_si') && r.d.trigger_layer !== 'phrase_hard')
      .map((r) => r.t);
    expect(weak).toEqual([]);
  });

  test('precision stays usable (>= 0.9) and every flag requires human review', () => {
    const tp = results.filter((r) => r.y === 1 && r.d.escalate).length;
    const fp = results.filter((r) => r.y === 0 && r.d.escalate).length;
    expect(tp / Math.max(1, tp + fp)).toBeGreaterThanOrEqual(0.9);
    results.filter((r) => r.d.escalate).forEach((r) => expect(r.d.requires_human_review).toBe(true));
  });
});

describe('decision contract', () => {
  const items = loadSet('crisis_eval_set.jsonl');
  const crisisItems = items.filter((i) => SI_CATEGORIES.has(i.c));

  test('idioms NEVER suppress an explicit ideation phrase', () => {
    const suffixes = [' this exam is killing me', ' lol dying laughing', ' im dead tired', ' to die for'];
    const missed = [];
    for (const it of crisisItems) {
      for (const s of suffixes) {
        for (const p of [null, 0.0, 0.99]) {
          if (!evaluateCrisis(it.t + s, p).escalate) missed.push(`${it.t}${s} @${p}`);
        }
      }
    }
    expect(missed).toEqual([]);
  });

  test('negation never suppresses (C-SSRS: any SI mention needs review)', () => {
    const d = evaluateCrisis("I'm not going to kill myself, just tired", 0.1);
    expect(d.escalate).toBe(true);
    expect(d.negation_present).toBe(true);
    expect(d.trigger_layer).toBe('phrase_hard');
  });

  test('low model probability never overrides a hard phrase', () => {
    expect(evaluateCrisis('I want to kill myself', 0.0).escalate).toBe(true);
    expect(evaluateCrisis('mar jaana chahta hoon', 0.01).escalate).toBe(true);
  });

  test('model-only severity tiers: review < 0.5 <= moderate < 0.75 <= high', () => {
    const t = 'everything is grey and heavy';
    expect(evaluateCrisis(t, 0.3)).toMatchObject({ escalate: false, review_only: false, severity: 'low' });
    // a hard phrase is never downgraded to review, even at low model probability
    expect(evaluateCrisis('I want to kill myself', 0.4)).toMatchObject({ escalate: true, review_only: false });
    expect(evaluateCrisis(t, 0.4)).toMatchObject({ escalate: false, review_only: true, severity: 'review', requires_human_review: true });
    expect(evaluateCrisis(t, 0.6)).toMatchObject({ escalate: true, review_only: false, severity: 'moderate' });
    expect(evaluateCrisis(t, 0.8)).toMatchObject({ escalate: true, severity: 'high' });
  });

  test('idiom suppresses only a model-only escalation', () => {
    const d = evaluateCrisis('This exam is killing me', 0.95);
    expect(d.escalate).toBe(false);
    expect(d.idiom_suppressed).toBe(true);
    expect(evaluateCrisis('this is so hard and i cant explain it', 0.95).escalate).toBe(true);
  });

  test('method/plan mentions are critical', () => {
    expect(evaluateCrisis("I've been saving up my pills", null).severity).toBe('critical');
    expect(evaluateCrisis('I tied a noose', null).severity).toBe('critical');
  });

  test('model threshold comes from the lexicon and is <= 0.5', () => {
    expect(ml.MODEL_THRESHOLD).toBeLessThanOrEqual(CRISIS_LEXICON.model_threshold);
    expect(ml.MODEL_THRESHOLD).toBeLessThanOrEqual(0.5);
  });

  test('malformed model payloads are treated as model unavailable', () => {
    expect(readModelProbability(null)).toBeNull();
    expect(readModelProbability({})).toBeNull();
    expect(readModelProbability({ probability_crisis: 'NaN' })).toBeNull();
    expect(readModelProbability({ probability_crisis: 7 })).toBeNull();
    expect(readModelProbability({ probability_crisis: 0.42 })).toBe(0.42);
  });
});

describe('POST /api/ml/predict fails SAFE when the ML service is down', () => {
  const layer = ml.stack.find((l) => l.route && l.route.path === '/predict');
  const handler = layer.route.stack[layer.route.stack.length - 1].handle;

  async function call(text, axiosImpl) {
    axios.post.mockImplementation(axiosImpl);
    const res = {
      statusCode: 200,
      body: null,
      status(c) { this.statusCode = c; return this; },
      json(b) { this.body = b; return this; },
    };
    await handler({ body: { text, patientId: 'p1' }, userId: 'p1', userRole: 'patient' }, res);
    return res;
  }

  const down = [
    ['connection refused', () => Promise.reject(Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' }))],
    ['timeout', () => Promise.reject(Object.assign(new Error('timeout of 1500ms exceeded'), { code: 'ECONNABORTED' }))],
    ['503 model missing', () => Promise.reject(Object.assign(new Error('Request failed with status code 503'), { response: { status: 503 } }))],
    ['malformed payload', () => Promise.resolve({ data: { crisis_detected: 'maybe' } })],
  ];

  test.each(down)('%s: hard phrase still escalates', async (_name, impl) => {
    const res = await call('I want to kill myself', impl);
    expect(res.statusCode).toBe(200);
    expect(res.body.available).toBe(true);
    expect(res.body.model_available).toBe(false);
    expect(res.body.degraded).toBe(true);
    expect(res.body.decision.escalate).toBe(true);
    expect(res.body.decision.trigger_layer).toBe('phrase_hard');
  });

  test.each(down)('%s: every crisis eval item escalates with the model down', async (_name, impl) => {
    const items = loadSet('crisis_eval_set.jsonl').filter((i) => i.y === 1);
    for (const it of items) {
      const res = await call(it.t, impl);
      expect({ t: it.t, escalate: res.body.decision.escalate }).toEqual({ t: it.t, escalate: true });
    }
  });

  test('model up: neutral text with low probability does not escalate', async () => {
    const res = await call('had a nice walk today', () =>
      Promise.resolve({ data: { crisis_detected: false, probability_crisis: 0.05, model_version: 'v1.0.0' } }));
    expect(res.body.model_available).toBe(true);
    expect(res.body.decision.escalate).toBe(false);
  });

  test('model up: model-only crisis escalates', async () => {
    const res = await call('everything is grey and heavy', () =>
      Promise.resolve({ data: { crisis_detected: true, probability_crisis: 0.8, model_version: 'v1.0.0' } }));
    expect(res.body.decision.escalate).toBe(true);
    expect(res.body.decision.trigger_layer).toBe('model');
  });

  test('missing text is rejected', async () => {
    const res = await call('', () => Promise.resolve({ data: {} }));
    expect(res.statusCode).toBe(400);
  });
});
