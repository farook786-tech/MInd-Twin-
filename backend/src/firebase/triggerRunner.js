'use strict';

/**
 * Runs Firestore "triggers" as realtime listeners (free Spark plan: no Cloud
 * Functions). Generic engine; the concrete listeners are in listenerSpecs.js.
 *
 * Correctness model
 * -----------------
 * A listener (onSnapshot) delivers EVERY matching doc when it (re)subscribes
 * and again after some reconnects. We must neither replay old history nor
 * lose changes made while the backend was down. Per listener we persist:
 *   watermark  server time (ms) up to which every change has been handled:
 *              the readTime of the last fully handled snapshot, held back
 *              below any change that is still failing/retrying;
 *   recent     keys of changes handled with time >= watermark - overlap.
 * A change is handled iff
 *   time >= watermark - overlap   (older = history, already handled) AND
 *   key not in recent/pending     (handled at most once per process state).
 * time/key are server metadata, never client clocks:
 *   kind 'create': time = doc.createTime, key = doc path   (once per doc)
 *   kind 'write':  time = doc.updateTime, key = path@updateTime (once per version)
 * The query itself is bounded by a server-timestamp field >= watermark -
 * overlap - querySlack, so a restart only reads recent docs (Spark quota).
 *
 * After a crash, changes handled since the last state flush are handled
 * again; every core handler is idempotent (deterministic crisis ids,
 * transactional push_receipts), so the effect is at-least-once with no
 * duplicate pushes. Several backend instances (laptop + Render) may run at
 * once for the same reason; each keeps its own state doc.
 *
 * Failures: a throwing handler is retried with exponential backoff (capped)
 * for as long as the process lives; the watermark never passes it, so it is
 * retried after a restart too. Listener errors resubscribe with exponential
 * backoff. Each listener processes its changes serially; a global semaphore
 * bounds handler concurrency across listeners.
 */

const DEFAULTS = Object.freeze({
  overlapMs: 2 * 60 * 1000,
  initialLookbackMs: 15 * 60 * 1000,
  maxCatchupMs: 24 * 60 * 60 * 1000,
  flushMs: 30 * 1000,
  resubscribeMs: 6 * 60 * 60 * 1000,
  concurrency: 4,
  retryBaseMs: 1000,
  retryMaxMs: 5 * 60 * 1000,
  errorBackoffBaseMs: 1000,
  errorBackoffMaxMs: 60 * 1000,
  querySlackMs: 5 * 60 * 1000,
});

function tsMillis(t) {
  if (!t) return null;
  if (typeof t.toMillis === 'function') return t.toMillis();
  if (t instanceof Date) return t.getTime();
  if (typeof t === 'number' && Number.isFinite(t)) return t;
  return null;
}

/** Sortable, exact version string of a Firestore Timestamp. */
function versionOf(t) {
  if (t && typeof t.seconds === 'number' && typeof t.nanoseconds === 'number') {
    return `${String(t.seconds).padStart(12, '0')}.${String(t.nanoseconds).padStart(9, '0')}`;
  }
  const ms = tsMillis(t);
  if (ms === null) return 'unknown';
  return `${String(Math.floor(ms / 1000)).padStart(12, '0')}.${String((ms % 1000) * 1e6).padStart(9, '0')}`;
}

function createSemaphore(limit) {
  let active = 0;
  const waiters = [];
  return {
    async acquire() {
      if (active < limit) {
        active += 1;
        return;
      }
      await new Promise((resolve) => waiters.push(resolve));
      active += 1;
    },
    release() {
      active -= 1;
      const next = waiters.shift();
      if (next) next();
    },
    get active() { return active; },
  };
}

class ListenerEngine {
  constructor(spec, runner) {
    this.spec = spec;
    this.runner = runner;
    this.kind = spec.kind === 'write' ? 'write' : 'create';
    this.querySlackMs = spec.querySlackMs ?? runner.options.querySlackMs;
    this.watermark = 0;
    this.recent = new Map(); // key -> time ms
    this.pending = new Map(); // key -> {time, attempts, run, timer}
    this.seen = new Map(); // path -> data (kind 'write': previous version)
    this.prevSeen = null;
    this.lastReadTime = null;
    this.queue = Promise.resolve();
    this.unsubscribe = null;
    this.subscribed = false;
    this.errorAttempts = 0;
    this.resubscribeTimer = null;
    this.refreshTimer = null;
    this.stopped = false;
    this.stats = {
      processed: 0, skippedOld: 0, skippedDuplicate: 0, failures: 0, errors: 0,
      lastSnapshotAt: null, lastEventAt: null, lastError: null, subscribedSince: null,
    };
  }

  get name() { return this.spec.name; }

  get cutoff() { return this.watermark - this.runner.options.overlapMs; }

  loadState(saved, now) {
    const { initialLookbackMs, maxCatchupMs, overlapMs } = this.runner.options;
    const log = this.runner.logger;
    if (!saved || typeof saved.watermark !== 'number') {
      this.watermark = now - initialLookbackMs;
      log.info(`listener ${this.name}: no saved state, starting ${Math.round(initialLookbackMs / 60000)} min back`);
    } else if (saved.watermark < now - maxCatchupMs) {
      this.watermark = now - maxCatchupMs;
      log.warn(`listener ${this.name}: saved watermark is older than the catch-up limit; ` +
        'changes before the limit are NOT processed', {
        savedWatermark: new Date(saved.watermark).toISOString(),
        maxCatchupHours: maxCatchupMs / 3600000,
      });
    } else {
      this.watermark = saved.watermark;
    }
    this.recent.clear();
    for (const entry of Array.isArray(saved && saved.recent) ? saved.recent : []) {
      const i = typeof entry === 'string' ? entry.indexOf('|') : -1;
      if (i <= 0) continue;
      const t = Number(entry.slice(0, i));
      if (Number.isFinite(t) && t >= this.watermark - overlapMs) this.recent.set(entry.slice(i + 1), t);
    }
  }

  saveState() {
    return {
      watermark: this.watermark,
      recent: [...this.recent].map(([k, t]) => `${t}|${k}`),
    };
  }

  enqueue(task) {
    this.queue = this.queue.then(task).catch((err) => {
      this.runner.logger.error(`listener ${this.name}: internal error`, { error: err && err.message, stack: err && err.stack });
    });
    return this.queue;
  }

  subscribe() {
    if (this.stopped) return;
    this.teardown();
    const { Timestamp } = this.runner;
    const since = Timestamp.fromMillis(Math.max(0, this.cutoff - this.querySlackMs));
    let query;
    try {
      query = this.spec.query(this.runner.db, since);
    } catch (err) {
      this.onError(err);
      return;
    }
    // Keep the previous version cache for 'before' lookups during the
    // initial snapshot of the new subscription; it is then dropped so the
    // cache only holds docs of the current result set.
    this.prevSeen = this.seen;
    this.seen = new Map();
    let first = true;
    this.unsubscribe = query.onSnapshot(
      (snapshot) => {
        const initial = first;
        first = false;
        this.enqueue(() => this.handleSnapshot(snapshot, initial));
      },
      (err) => this.onError(err),
    );
    this.subscribed = true;
    this.stats.subscribedSince = new Date(this.runner.now()).toISOString();
    const refreshMs = this.runner.options.resubscribeMs;
    if (refreshMs > 0) {
      this.refreshTimer = this.runner.setTimer(() => {
        this.refreshTimer = null;
        // Through the queue so pending snapshot work finishes first.
        this.enqueue(() => this.subscribe());
      }, refreshMs);
    }
  }

  teardown() {
    if (this.unsubscribe) {
      try {
        this.unsubscribe();
      } catch {
        // ignore
      }
    }
    this.unsubscribe = null;
    this.subscribed = false;
    if (this.refreshTimer) this.runner.clearTimer(this.refreshTimer);
    this.refreshTimer = null;
  }

  onError(err) {
    this.teardown();
    if (this.stopped) return;
    this.stats.errors += 1;
    const code = err && (err.code !== undefined ? err.code : err.status);
    this.stats.lastError = `${code !== undefined ? `${code} ` : ''}${err && err.message}`;
    const { errorBackoffBaseMs, errorBackoffMaxMs } = this.runner.options;
    const delay = Math.min(errorBackoffMaxMs, errorBackoffBaseMs * 2 ** this.errorAttempts);
    this.errorAttempts += 1;
    const hint = (code === 9 || code === 'failed-precondition' || /index/i.test(String(err && err.message))) ?
      ' (missing index? deploy firestore.indexes.json: firebase deploy --only firestore:indexes)' : '';
    this.runner.logger.error(`listener ${this.name} failed; resubscribing in ${delay} ms${hint}`, {
      code, error: err && err.message, attempt: this.errorAttempts,
    });
    if (this.resubscribeTimer) this.runner.clearTimer(this.resubscribeTimer);
    this.resubscribeTimer = this.runner.setTimer(() => {
      this.resubscribeTimer = null;
      this.enqueue(() => this.subscribe());
    }, delay);
  }

  async handleSnapshot(snapshot, initial) {
    if (this.stopped) return;
    this.errorAttempts = 0;
    this.stats.lastSnapshotAt = new Date(this.runner.now()).toISOString();
    const changes = typeof snapshot.docChanges === 'function' ? snapshot.docChanges() : [];
    for (const change of changes) {
      if (this.stopped) return;
      await this.processChange(change);
    }
    if (initial) this.prevSeen = null;
    const readTime = tsMillis(snapshot.readTime);
    if (readTime !== null) this.advanceWatermark(readTime);
  }

  /**
   * Moves the watermark to the newest fully handled snapshot readTime, but
   * never past a change that is still pending retry. Called with null after
   * a retry succeeds (re-uses the last known readTime).
   */
  advanceWatermark(readTimeMs) {
    if (readTimeMs !== null && readTimeMs !== undefined) {
      this.lastReadTime = Math.max(this.lastReadTime || 0, readTimeMs);
    }
    if (!this.lastReadTime) return;
    let target = this.lastReadTime;
    for (const p of this.pending.values()) target = Math.min(target, p.time - 1);
    if (target > this.watermark) {
      this.watermark = target;
      const floor = this.watermark - this.runner.options.overlapMs;
      for (const [k, t] of this.recent) if (t < floor) this.recent.delete(k);
      this.runner.markDirty();
    }
  }

  async processChange(change) {
    const doc = change.doc;
    const path = doc && doc.ref && doc.ref.path;
    if (!path) return;
    if (change.type === 'removed') {
      this.seen.delete(path);
      return;
    }
    if (this.spec.filter && !this.spec.filter(doc)) return;

    let before = null;
    if (this.kind === 'write') {
      if (this.seen.has(path)) before = this.seen.get(path);
      else if (this.prevSeen && this.prevSeen.has(path)) before = this.prevSeen.get(path);
      this.seen.set(path, doc.data());
    }

    let key;
    let time;
    if (this.kind === 'create') {
      if (change.type === 'modified') return; // create handlers ignore updates
      key = path;
      time = tsMillis(doc.createTime);
    } else {
      key = `${path}@${versionOf(doc.updateTime)}`;
      time = tsMillis(doc.updateTime);
    }
    if (time === null) {
      this.runner.logger.warn(`listener ${this.name}: change without server time; skipped`, { path });
      return;
    }
    if (time < this.cutoff) {
      this.stats.skippedOld += 1;
      return;
    }
    if (this.recent.has(key) || this.pending.has(key)) {
      this.stats.skippedDuplicate += 1;
      return;
    }
    const run = () => this.spec.handle({ doc, before, change });
    await this.attempt(key, time, run, 0);
  }

  async attempt(key, time, run, attempts) {
    const { semaphore, logger, options } = this.runner;
    await semaphore.acquire();
    try {
      await run();
      this.pending.delete(key);
      this.recent.set(key, time);
      this.stats.processed += 1;
      this.stats.lastEventAt = new Date(this.runner.now()).toISOString();
      this.runner.noteEvent();
      this.runner.markDirty();
    } catch (err) {
      const n = attempts + 1;
      this.stats.failures += 1;
      const delay = Math.min(options.retryMaxMs, options.retryBaseMs * 2 ** Math.min(n - 1, 20));
      const retryable = err && (err.retryable || err.name === 'ReceiptBusyError');
      (retryable ? logger.warn : logger.error)(`listener ${this.name}: handler failed; retry in ${delay} ms`, {
        key, attempt: n, error: err && err.message,
      });
      const entry = { time, attempts: n, run, timer: null };
      this.pending.set(key, entry);
      if (!this.stopped) {
        entry.timer = this.runner.setTimer(() => {
          entry.timer = null;
          this.enqueue(async () => {
            if (this.stopped || this.pending.get(key) !== entry) return;
            await this.attempt(key, time, run, n);
            this.advanceWatermark(null);
          });
        }, delay);
      }
    } finally {
      semaphore.release();
    }
  }

  stop() {
    this.stopped = true;
    this.teardown();
    if (this.resubscribeTimer) this.runner.clearTimer(this.resubscribeTimer);
    this.resubscribeTimer = null;
    for (const p of this.pending.values()) if (p.timer) this.runner.clearTimer(p.timer);
    return this.queue;
  }

  status() {
    return {
      name: this.name,
      subscribed: this.subscribed,
      watermark: this.watermark ? new Date(this.watermark).toISOString() : null,
      pendingRetries: this.pending.size,
      ...this.stats,
    };
  }
}

/**
 * @param {object} p
 * @param {FirebaseFirestore.Firestore} p.db
 * @param {{fromMillis(ms:number): unknown}} p.Timestamp
 * @param {Array<object>} p.specs listener specs (see listenerSpecs.js)
 * @param {{load(): Promise<object|null>, save(state: object): Promise<void>}} p.stateStore
 * @param {object} p.logger {info, warn, error}
 * @param {object} [p.options] overrides of DEFAULTS
 * @param {() => number} [p.now]
 * @param {Function} [p.setTimer] (fn, ms) => handle
 * @param {Function} [p.clearTimer]
 */
function createTriggerRunner({
  db, Timestamp, specs, stateStore, logger, options = {},
  now = () => Date.now(), setTimer, clearTimer,
}) {
  const opts = { ...DEFAULTS };
  for (const [k, v] of Object.entries(options)) if (v !== undefined && v !== null) opts[k] = v;
  if (opts.overlapMs < opts.flushMs) {
    logger.warn('runner overlap window is shorter than the state flush interval');
  }
  const timers = new Set();
  const runner = {
    db,
    Timestamp,
    logger,
    options: opts,
    now,
    semaphore: createSemaphore(Math.max(1, opts.concurrency)),
    setTimer: setTimer || ((fn, ms) => {
      const h = setTimeout(() => {
        timers.delete(h);
        fn();
      }, ms);
      if (h.unref) h.unref();
      timers.add(h);
      return h;
    }),
    clearTimer: clearTimer || ((h) => {
      timers.delete(h);
      clearTimeout(h);
    }),
    dirty: false,
    lastEventAt: null,
    markDirty() { runner.dirty = true; },
    noteEvent() { runner.lastEventAt = new Date(now()).toISOString(); },
  };
  const engines = specs.map((s) => new ListenerEngine(s, runner));
  let flushTimer = null;
  let started = false;
  let startedAt = null;

  async function flush() {
    if (!runner.dirty) return;
    runner.dirty = false;
    const state = { version: 1, listeners: {} };
    for (const e of engines) state.listeners[e.name] = e.saveState();
    try {
      await stateStore.save(state);
    } catch (err) {
      runner.dirty = true;
      logger.error('runner state flush failed (will retry)', { error: err && err.message });
    }
  }

  function scheduleFlush() {
    flushTimer = runner.setTimer(async () => {
      await flush();
      if (started) scheduleFlush();
    }, opts.flushMs);
  }

  async function start() {
    if (started) return;
    let saved = null;
    try {
      saved = await stateStore.load();
    } catch (err) {
      // Refuse to guess: without state we could replay or skip history.
      logger.error('runner state could not be loaded; listeners NOT started', { error: err && err.message });
      throw err;
    }
    const t = now();
    for (const e of engines) e.loadState(saved && saved.listeners && saved.listeners[e.name], t);
    started = true;
    startedAt = new Date(t).toISOString();
    for (const e of engines) e.subscribe();
    scheduleFlush();
    logger.info(`trigger runner started; active listeners: ${engines.map((e) => e.name).join(', ')}`);
  }

  async function stop() {
    if (!started) return;
    started = false;
    if (flushTimer) runner.clearTimer(flushTimer);
    flushTimer = null;
    await Promise.all(engines.map((e) => e.stop()));
    runner.dirty = true;
    await flush();
    for (const h of timers) clearTimeout(h);
    timers.clear();
    logger.info('trigger runner stopped');
  }

  function status() {
    return {
      enabled: true,
      started,
      startedAt,
      listeners: engines.map((e) => e.status()),
      lastEventAt: runner.lastEventAt,
    };
  }

  /** Waits until every listener queue is idle (tests). */
  async function idle() {
    for (let i = 0; i < 3; i += 1) await Promise.all(engines.map((e) => e.queue));
  }

  return { start, stop, flush, status, idle, engines, options: opts };
}

module.exports = { createTriggerRunner, versionOf, tsMillis, DEFAULTS };
