'use strict';

/**
 * POST /api/callable/:name — token verification (mocked), authContext,
 * error-code -> HTTP status mapping, rate limiting.
 */

const express = require('express');
const { createCallableRouter, HTTP_STATUS } = require('../src/firebase/callableRouter');
const { loadCoreModule } = require('../src/firebase/coreLoader');

const { runCallable, CALLABLE_NAMES, errors } = loadCoreModule();
const { CallableError, InviteCodeError } = errors;
const quietLogger = { info: () => {}, warn: () => {}, error: () => {} };

function startServer({ verifyIdToken, callables, limits, firebaseReady = true }) {
  const app = express();
  app.use(express.json());
  app.use('/api/callable', createCallableRouter({
    getAuth: () => (firebaseReady ? { verifyIdToken } : null),
    getCallables: () => (firebaseReady ? callables : null),
    runCallable,
    names: CALLABLE_NAMES,
    logger: quietLogger,
    limits,
  }));
  return new Promise((resolve) => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, base: `http://127.0.0.1:${server.address().port}/api/callable` });
    });
  });
}

async function post(base, name, { token, body } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(`${base}/${name}`, {
    method: 'POST', headers, body: JSON.stringify(body === undefined ? { data: {} } : body),
  });
  return { status: res.status, json: await res.json() };
}

function authErr(code) {
  const e = new Error(code);
  e.code = code;
  return e;
}

describe('/api/callable', () => {
  let ctx;
  const calls = [];
  const verifyIdToken = jest.fn(async (token) => {
    if (token === 'good') return { uid: 'u1', role: 'therapist', email: 'a@b.c', admin: false };
    if (token === 'admin') return { uid: 'adm', admin: true };
    if (token === 'revoked') throw authErr('auth/id-token-revoked');
    if (token === 'expired') throw authErr('auth/id-token-expired');
    if (token === 'disabled') throw authErr('auth/user-disabled');
    throw authErr('app/network-error');
  });
  let behaviour = async () => ({ inviteCode: 'ABCD2345' });
  const callables = Object.fromEntries(CALLABLE_NAMES.map((n) => [n, async (authContext, data) => {
    calls.push({ name: n, authContext, data });
    return behaviour(authContext, data);
  }]));

  beforeAll(async () => {
    ctx = await startServer({
      verifyIdToken, callables,
      limits: { perUid: { capacity: 1000, windowMs: 60000 }, perIp: { capacity: 1000, windowMs: 60000 } },
    });
  });
  afterAll(() => new Promise((r) => ctx.server.close(r)));
  beforeEach(() => {
    calls.length = 0;
    verifyIdToken.mockClear();
    behaviour = async () => ({ inviteCode: 'ABCD2345' });
  });

  test('success: verifies token with checkRevoked=true and passes authContext + data', async () => {
    const r = await post(ctx.base, 'getMyInviteCode', { token: 'good', body: { data: { x: 1 } } });
    expect(r.status).toBe(200);
    expect(r.json).toEqual({ data: { inviteCode: 'ABCD2345' } });
    expect(verifyIdToken).toHaveBeenCalledWith('good', true);
    expect(calls).toHaveLength(1);
    expect(calls[0].authContext.uid).toBe('u1');
    expect(calls[0].authContext.token.role).toBe('therapist');
    expect(calls[0].data).toEqual({ x: 1 });
  });

  test('all five callables are routed', async () => {
    for (const name of CALLABLE_NAMES) {
      const r = await post(ctx.base, name, { token: 'good' });
      expect(r.status).toBe(200);
    }
    expect(calls.map((c) => c.name)).toEqual([...CALLABLE_NAMES]);
  });

  test('unknown function -> 404 not-found, never verifies the token', async () => {
    const r = await post(ctx.base, 'deleteEverything', { token: 'good' });
    expect(r.status).toBe(404);
    expect(r.json.error.code).toBe('not-found');
    expect(verifyIdToken).not.toHaveBeenCalled();
  });

  test('missing / malformed Authorization -> 401 unauthenticated', async () => {
    let r = await post(ctx.base, 'getMyInviteCode');
    expect(r.status).toBe(401);
    expect(r.json.error.code).toBe('unauthenticated');
    const res = await fetch(`${ctx.base}/getMyInviteCode`, {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Basic abc' }, body: '{}',
    });
    expect(res.status).toBe(401);
    r = await post(ctx.base, 'getMyInviteCode', { token: 'good' });
    expect(r.status).toBe(200);
    expect(calls).toHaveLength(1);
  });

  test.each(['revoked', 'expired', 'disabled'])('%s token -> 401 and handler not called', async (token) => {
    const r = await post(ctx.base, 'registerPatient', { token });
    expect(r.status).toBe(401);
    expect(r.json.error.code).toBe('unauthenticated');
    expect(calls).toHaveLength(0);
  });

  test('token verification infrastructure failure -> 503 unavailable', async () => {
    const r = await post(ctx.base, 'registerPatient', { token: 'boom' });
    expect(r.status).toBe(503);
    expect(r.json.error.code).toBe('unavailable');
    expect(calls).toHaveLength(0);
  });

  test.each([
    ['invalid-argument', 400],
    ['unauthenticated', 401],
    ['permission-denied', 403],
    ['not-found', 404],
    ['already-exists', 409],
    ['failed-precondition', 412],
    ['internal', 500],
  ])('CallableError %s -> HTTP %i with {error:{code,message}}', async (code, status) => {
    behaviour = async () => { throw new CallableError(code, `msg for ${code}`); };
    const r = await post(ctx.base, 'joinTherapist', { token: 'good' });
    expect(r.status).toBe(status);
    expect(HTTP_STATUS[code]).toBe(status);
    expect(r.json.error.code).toBe(code);
    if (code !== 'internal') expect(r.json.error.message).toBe(`msg for ${code}`);
  });

  test('InviteCodeError keeps its code', async () => {
    behaviour = async () => { throw new InviteCodeError('not-found', 'Invite code not found or no longer active.'); };
    const r = await post(ctx.base, 'registerPatient', { token: 'good' });
    expect(r.status).toBe(404);
    expect(r.json.error).toEqual({ code: 'not-found', message: 'Invite code not found or no longer active.' });
  });

  test('ValidationError -> 400 invalid-argument', async () => {
    behaviour = async () => {
      const e = new Error('name is required.');
      e.name = 'ValidationError';
      throw e;
    };
    const r = await post(ctx.base, 'registerTherapist', { token: 'good' });
    expect(r.status).toBe(400);
    expect(r.json.error).toEqual({ code: 'invalid-argument', message: 'name is required.' });
  });

  test('unexpected error -> 500 internal with a generic message (no internals leaked)', async () => {
    behaviour = async () => { throw new Error('FIRESTORE secret path /x/y exploded'); };
    const r = await post(ctx.base, 'approveTherapist', { token: 'admin' });
    expect(r.status).toBe(500);
    expect(r.json.error.code).toBe('internal');
    expect(r.json.error.message).not.toMatch(/secret|FIRESTORE/);
  });

  test('missing body.data -> core receives undefined (treated as {})', async () => {
    const r = await post(ctx.base, 'getMyInviteCode', { token: 'good', body: {} });
    expect(r.status).toBe(200);
    expect(calls[0].data).toBeUndefined();
  });

  test('real core validation runs end to end (registerTherapist without name)', async () => {
    const { createCore } = loadCoreModule();
    const core = createCore({
      db: () => { throw new Error('db must not be touched before validation'); },
      auth: () => ({}), messaging: () => ({}),
      FieldValue: {}, Timestamp: {}, logger: quietLogger,
    });
    const s = await startServer({ verifyIdToken, callables: core.callables });
    try {
      const r = await post(s.base, 'registerTherapist', { token: 'good', body: { data: { name: '' } } });
      expect(r.status).toBe(400);
      expect(r.json.error.code).toBe('invalid-argument');
      const r2 = await post(s.base, 'getMyInviteCode', { token: 'expired' });
      expect(r2.status).toBe(401);
      // pending therapist (no role claim) -> permission-denied before any db access
      const r3 = await post(s.base, 'approveTherapist', { token: 'good', body: { data: { therapistUid: 'x' } } });
      expect(r3.status).toBe(403);
      expect(r3.json.error.code).toBe('permission-denied');
    } finally {
      await new Promise((r) => s.server.close(r));
    }
  });
});

describe('/api/callable rate limiting and setup', () => {
  test('per-uid limit -> 429 resource-exhausted', async () => {
    const verifyIdToken = async (t) => ({ uid: `rl-${t}` });
    const callables = Object.fromEntries(CALLABLE_NAMES.map((n) => [n, async () => ({ ok: true })]));
    const s = await startServer({
      verifyIdToken, callables,
      limits: { perUid: { capacity: 2, windowMs: 60000 }, perIp: { capacity: 100, windowMs: 60000 } },
    });
    try {
      expect((await post(s.base, 'getMyInviteCode', { token: 'a' })).status).toBe(200);
      expect((await post(s.base, 'getMyInviteCode', { token: 'a' })).status).toBe(200);
      const r = await post(s.base, 'getMyInviteCode', { token: 'a' });
      expect(r.status).toBe(429);
      expect(r.json.error.code).toBe('resource-exhausted');
      // another user is not affected
      expect((await post(s.base, 'getMyInviteCode', { token: 'b' })).status).toBe(200);
    } finally {
      await new Promise((r) => s.server.close(r));
    }
  });

  test('without Firebase credentials -> 503 unavailable', async () => {
    const s = await startServer({ verifyIdToken: async () => ({}), callables: {}, firebaseReady: false });
    try {
      const r = await post(s.base, 'registerPatient', { token: 'x' });
      expect(r.status).toBe(503);
      expect(r.json.error.code).toBe('unavailable');
    } finally {
      await new Promise((r) => s.server.close(r));
    }
  });
});
