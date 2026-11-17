'use strict';

/**
 * Free-plan (Spark) replacement for Cloud Functions, hosted by the backend:
 *   (a) POST /api/callable/:name  — the five callables (callableRouter.js)
 *   (b) realtime-listener triggers (triggerRunner.js + listenerSpecs.js)
 *   (c) periodic orphan sweep instead of the Auth onDelete trigger
 *       (orphanSweep.js), plus POST /api/runner/cleanup-orphans for admins.
 * All three run the SAME core logic as functions/ (functions/src/core).
 *
 * Environment
 *   FUNCTIONS_RUNNER_ENABLED=false   disable (b) and (c); callables stay on
 *   RUNNER_INSTANCE_ID               state doc id (default: 'render' on Render, else hostname)
 *   RUNNER_OVERLAP_MS                re-check window behind the watermark (default 120000)
 *   RUNNER_INITIAL_LOOKBACK_MS       first start without state (default 900000 = 15 min)
 *   RUNNER_MAX_CATCHUP_MS            max replay after downtime (default 86400000 = 24 h)
 *   RUNNER_FLUSH_MS                  state persist interval (default 30000)
 *   RUNNER_CONCURRENCY               max concurrent handlers (default 4)
 *   RUNNER_ORPHAN_SWEEP_HOURS        orphan sweep period, 0 = off (default 24)
 */

const os = require('os');
const express = require('express');
const { getFirebaseAdmin } = require('../services/FirebaseAdmin');
const { createBackendCore, loadCoreModule, createConsoleLogger } = require('./coreLoader');
const { createCallableRouter } = require('./callableRouter');
const { createTriggerRunner } = require('./triggerRunner');
const { buildListenerSpecs } = require('./listenerSpecs');
const { createFirestoreStateStore } = require('./runnerState');
const { sweepOrphanedAccounts } = require('./orphanSweep');

function intEnv(env, name) {
  const raw = env[name];
  if (raw === undefined || raw === '') return undefined;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : undefined;
}

function defaultInstanceId(env) {
  if (env.RUNNER_INSTANCE_ID) return String(env.RUNNER_INSTANCE_ID).replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 100);
  if (env.RENDER) return 'render';
  return `host_${os.hostname().replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 80)}`;
}

/**
 * Builds the runner around an initialized firebase-admin namespace.
 * Exposed separately so the emulator smoke test can inject a fake messaging.
 */
function buildRunner({ admin, env = process.env, coreOverrides = {}, logger = createConsoleLogger('[runner]') }) {
  const core = createBackendCore(admin, coreOverrides);
  const db = core.deps.db;
  const specs = buildListenerSpecs({ core, db, FieldValue: admin.firestore.FieldValue, logger });
  const instanceId = defaultInstanceId(env);
  const runner = createTriggerRunner({
    db: db(),
    Timestamp: admin.firestore.Timestamp,
    specs,
    stateStore: createFirestoreStateStore({ db, FieldValue: admin.firestore.FieldValue, instanceId }),
    logger,
    options: {
      overlapMs: intEnv(env, 'RUNNER_OVERLAP_MS'),
      initialLookbackMs: intEnv(env, 'RUNNER_INITIAL_LOOKBACK_MS'),
      maxCatchupMs: intEnv(env, 'RUNNER_MAX_CATCHUP_MS'),
      flushMs: intEnv(env, 'RUNNER_FLUSH_MS'),
      concurrency: intEnv(env, 'RUNNER_CONCURRENCY'),
    },
  });
  return { core, runner, instanceId };
}

/**
 * Mounts the routes on `app` and (unless disabled) starts the listeners.
 * @return {{status(): object, stop(): Promise<void>}}
 */
function setupFunctionsRunner(app, { env = process.env } = {}) {
  const logger = createConsoleLogger('[functions]');
  const { runCallable, CALLABLE_NAMES } = loadCoreModule();
  const admin = getFirebaseAdmin();
  let core = null;
  if (admin) {
    try {
      core = createBackendCore(admin);
    } catch (err) {
      logger.error('shared core could not be created; callables disabled', { error: err.message });
    }
  } else {
    logger.error('Firebase Admin SDK unavailable: /api/callable will answer 503 and no triggers run. ' +
      'Set GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_APPLICATION_CREDENTIALS_JSON.');
  }

  app.use('/api/callable', createCallableRouter({
    getAuth: () => (admin && core ? admin.auth() : null),
    getCallables: () => (core ? core.callables : null),
    runCallable,
    names: CALLABLE_NAMES,
    logger,
  }));

  const enabled = env.FUNCTIONS_RUNNER_ENABLED !== 'false' && env.NODE_ENV !== 'test';
  let built = null;
  let sweepTimer = null;
  let lastSweep = null;
  const disabledReason = !enabled ? 'FUNCTIONS_RUNNER_ENABLED=false' : (!admin || !core ? 'no Firebase credentials' : null);

  async function runSweep(opts = {}) {
    const summary = await sweepOrphanedAccounts({
      db: core.deps.db,
      auth: core.deps.auth,
      cleanupDeletedUser: core.triggers.cleanupDeletedUser,
      logger,
      ...opts,
    });
    lastSweep = { at: new Date().toISOString(), cleaned: summary.cleaned.length, aborted: summary.aborted, dryRun: summary.dryRun };
    return summary;
  }

  // Admin-only manual trigger of the orphan sweep (Auth deletions).
  const adminRouter = express.Router();
  adminRouter.post('/cleanup-orphans', async (req, res) => {
    if (!admin || !core) return res.status(503).json({ error: { code: 'unavailable', message: 'Firebase not configured.' } });
    const m = /^Bearer\s+(\S+)$/i.exec(String(req.get('authorization') || ''));
    if (!m) return res.status(401).json({ error: { code: 'unauthenticated', message: 'Sign in first.' } });
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(m[1], true);
    } catch {
      return res.status(401).json({ error: { code: 'unauthenticated', message: 'Invalid or expired token.' } });
    }
    if (decoded.admin !== true) {
      return res.status(403).json({ error: { code: 'permission-denied', message: 'Administrator access required.' } });
    }
    try {
      const body = req.body && typeof req.body === 'object' ? req.body : {};
      const summary = await runSweep({ dryRun: body.dryRun === true, force: body.force === true });
      return res.json({ data: { ...summary, cleaned: summary.cleaned.length } });
    } catch (err) {
      logger.error('orphan sweep failed', { error: err.message });
      return res.status(500).json({ error: { code: 'internal', message: 'Orphan sweep failed.' } });
    }
  });
  app.use('/api/runner', adminRouter);

  if (!disabledReason) {
    built = buildRunner({ admin, env });
    built.runner.start().catch((err) => {
      logger.error('trigger runner failed to start; retrying in 30 s', { error: err.message });
      const retry = setInterval(() => {
        built.runner.start().then(() => clearInterval(retry)).catch((e) =>
          logger.error('trigger runner start retry failed', { error: e.message }));
      }, 30 * 1000);
      if (retry.unref) retry.unref();
    });
    const sweepHours = intEnv(env, 'RUNNER_ORPHAN_SWEEP_HOURS') ?? 24;
    if (sweepHours > 0) {
      const tick = () => runSweep().catch((err) => logger.error('orphan sweep failed', { error: err.message }));
      // First sweep shortly after start, then periodically.
      const first = setTimeout(tick, 2 * 60 * 1000);
      if (first.unref) first.unref();
      sweepTimer = setInterval(tick, sweepHours * 3600 * 1000);
      if (sweepTimer.unref) sweepTimer.unref();
    }
  } else {
    logger.warn(`trigger runner disabled (${disabledReason}): no vital/crisis checks, no pushes from this server`);
  }

  return {
    status() {
      if (!built) return { enabled: false, reason: disabledReason, listeners: [], lastEventAt: null };
      const s = built.runner.status();
      return {
        enabled: true,
        instanceId: built.instanceId,
        started: s.started,
        listeners: s.listeners.map((l) => ({
          name: l.name,
          subscribed: l.subscribed,
          watermark: l.watermark,
          processed: l.processed,
          pendingRetries: l.pendingRetries,
          errors: l.errors,
          lastError: l.lastError,
          lastSnapshotAt: l.lastSnapshotAt,
        })),
        lastEventAt: s.lastEventAt,
        orphanSweep: lastSweep,
      };
    },
    async stop() {
      if (sweepTimer) clearInterval(sweepTimer);
      if (built) await built.runner.stop();
    },
  };
}

module.exports = { setupFunctionsRunner, buildRunner, defaultInstanceId };
