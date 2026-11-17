/**
 * POST /api/clinical/phq9 must await the async assessment, return 201 with the
 * real result (incl. item-9 safety flag), 400 on invalid responses, 500 on
 * unexpected failures — never 201 with {}.
 */
jest.mock('../src/middleware/auth', () => ({
  authMiddleware: (req, res, next) => next(),
  requirePatientAccess: (req, res, next) => next(),
  requireTherapistSelf: (req, res, next) => next(),
  requireRole: () => (req, res, next) => next(),
}));
jest.mock('../src/database/Database', () => ({ getInstance: () => ({ getDB: () => null }) }));

const ClinicalService = require('../src/services/ClinicalService');
const router = require('../src/routes/clinical');

const layer = router.stack.find((l) => l.route && l.route.path === '/phq9' && l.route.methods.post);
const handler = layer.route.stack[layer.route.stack.length - 1].handle;

async function call(body) {
  const res = {
    statusCode: 200,
    body: null,
    status(c) { this.statusCode = c; return this; },
    json(b) { this.body = b; return this; },
  };
  await handler({ body }, res);
  return res;
}

const base = { patientId: 'p1', therapistId: 't1' };

afterEach(() => jest.restoreAllMocks());

describe('POST /api/clinical/phq9', () => {
  test('awaits the assessment and returns its result (201)', async () => {
    jest.spyOn(ClinicalService.prototype, 'createPHQ9Assessment').mockResolvedValue({
      assessmentId: 'a1', score: 1, severity: 'minimal', suicidalIdeation: true, requiresSafetyAssessment: true,
    });
    const res = await call({ ...base, responses: [0, 0, 0, 0, 0, 0, 0, 0, 1] });
    expect(res.statusCode).toBe(201);
    expect(res.body.assessment).toMatchObject({ assessmentId: 'a1', suicidalIdeation: true });
  });

  test('invalid responses -> 400 (real scorePHQ9 validation, not 201 {})', async () => {
    jest.spyOn(console, 'error').mockImplementation(() => {});
    for (const responses of [[0, 0, 0, 0, 0, 0, 0, 0, 2.7], [0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, '3abc']]) {
      const res = await call({ ...base, responses });
      expect(res.statusCode).toBe(400);
      expect(res.body.error).toMatch(/PHQ-9 requires|Each response must/);
    }
  });

  test('missing fields -> 400', async () => {
    expect((await call({ patientId: 'p1', responses: [] })).statusCode).toBe(400);
  });

  test('unexpected async failure -> 500, not an unhandled rejection', async () => {
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(ClinicalService.prototype, 'createPHQ9Assessment').mockRejectedValue(new Error('SQLITE_BUSY'));
    const res = await call({ ...base, responses: new Array(9).fill(1) });
    expect(res.statusCode).toBe(500);
    expect(res.body).toEqual({ error: 'Failed to save PHQ-9 assessment' });
  });
});
