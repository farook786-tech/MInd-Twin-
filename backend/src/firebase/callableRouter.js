'use strict';

/**
 * POST /api/callable/:name — the five MindTwin callables served by the
 * backend (free Spark plan; Cloud Functions would need Blaze).
 *
 * Request:  Authorization: Bearer <Firebase ID token>, body {data: {...}}
 * Response: 200 {data: result} | <status> {error: {code, message}}
 *
 * The ID token is verified with checkRevoked=true; authContext is
 * {uid, token: decodedToken} exactly like request.auth in onCall, and the
 * shared core logic (functions/src/core/callables.js) is executed.
 */

const express = require('express');
const TokenBucketMiddleware = require('../middleware/TokenBucketMiddleware');

const HTTP_STATUS = Object.freeze({
  'invalid-argument': 400,
  unauthenticated: 401,
  'permission-denied': 403,
  'not-found': 404,
  'already-exists': 409,
  'failed-precondition': 412,
  'resource-exhausted': 429,
  internal: 500,
  unavailable: 503,
  'deadline-exceeded': 504,
});

function statusFor(code) {
  return HTTP_STATUS[code] || 500;
}

function sendError(res, code, message) {
  const c = HTTP_STATUS[code] ? code : 'internal';
  res.status(statusFor(c)).json({ error: { code: c, message } });
}

// Token errors that mean "this token is not acceptable" (client must sign in
// again). Anything else (network to Google, internal) is 'unavailable'.
const AUTH_REJECT = new Set([
  'auth/id-token-expired',
  'auth/id-token-revoked',
  'auth/user-disabled',
  'auth/user-not-found',
  'auth/argument-error',
  'auth/invalid-id-token',
  'auth/invalid-argument',
]);

function rateLimitedJson(limiter) {
  // Re-shape the limiter's 429 body into the callable error envelope.
  return (req, res, next) => {
    const json = res.json.bind(res);
    res.json = (body) => {
      if (res.statusCode === 429) {
        return json({ error: { code: 'resource-exhausted', message: 'Too many requests. Please wait a minute and try again.' } });
      }
      return json(body);
    };
    limiter(req, res, (err) => {
      res.json = json;
      next(err);
    });
  };
}

/**
 * @param {object} p
 * @param {() => ({verifyIdToken(t: string, checkRevoked: boolean): Promise<object>})|null} p.getAuth
 * @param {() => object|null} p.getCallables core callables, or null when Firebase is unavailable
 * @param {Function} p.runCallable shared runCallable(name, fn, authContext, data, logger)
 * @param {readonly string[]} p.names allowed callable names
 * @param {object} p.logger
 * @param {{perUid?: {capacity: number, windowMs: number}, perIp?: {capacity: number, windowMs: number}}} [p.limits]
 */
function createCallableRouter({ getAuth, getCallables, runCallable, names, logger, limits = {} }) {
  const router = express.Router();
  const allowed = new Set(names);
  const perIp = limits.perIp || { capacity: 60, windowMs: 60 * 1000 };
  const perUid = limits.perUid || { capacity: 20, windowMs: 60 * 1000 };
  const ipLimiter = rateLimitedJson(TokenBucketMiddleware({
    ...perIp, keyFn: (req) => `callable-ip:${req.ip}`,
  }));
  const uidLimiter = rateLimitedJson(TokenBucketMiddleware({
    ...perUid, keyFn: (req) => `callable-uid:${req.callableUid}`,
  }));

  router.post('/:name', ipLimiter, async (req, res, next) => {
    const { name } = req.params;
    if (!allowed.has(name)) return sendError(res, 'not-found', `Unknown function ${name}.`);
    const callables = getCallables();
    const auth = getAuth();
    if (!callables || !auth) {
      return sendError(res, 'unavailable', 'The MindTwin server is not connected to Firebase. Ask the clinic to check the server setup.');
    }
    const header = String(req.get('authorization') || '');
    const m = /^Bearer\s+(\S+)$/i.exec(header);
    if (!m) return sendError(res, 'unauthenticated', 'Sign in first.');
    let decoded;
    try {
      decoded = await auth.verifyIdToken(m[1], true);
    } catch (err) {
      const code = err && (err.code || (err.errorInfo && err.errorInfo.code));
      if (code && AUTH_REJECT.has(code)) {
        logger.warn('callable token rejected', { name, code });
        return sendError(res, 'unauthenticated', 'Your session expired. Please sign in again.');
      }
      logger.error('callable token verification failed', { name, code, error: err && err.message });
      return sendError(res, 'unavailable', 'Could not verify your sign-in right now. Please try again.');
    }
    req.callableUid = decoded.uid;
    req.callableToken = decoded;
    return next();
  }, uidLimiter, async (req, res) => {
    const { name } = req.params;
    const body = req.body;
    const data = body && typeof body === 'object' && !Array.isArray(body) ? body.data : undefined;
    const authContext = { uid: req.callableUid, token: req.callableToken };
    try {
      const callables = getCallables();
      const result = await runCallable(name, callables[name], authContext, data, logger);
      res.status(200).json({ data: result === undefined ? null : result });
    } catch (err) {
      const code = err && typeof err.code === 'string' ? err.code : 'internal';
      const message = code === 'internal' || !err || !err.message ?
        'Unexpected error. Please try again.' : err.message;
      if (code === 'internal') logger.error('callable internal error', { name, uid: req.callableUid });
      else logger.info('callable rejected', { name, uid: req.callableUid, code });
      sendError(res, code, message);
    }
  });

  return router;
}

module.exports = { createCallableRouter, HTTP_STATUS, statusFor };
