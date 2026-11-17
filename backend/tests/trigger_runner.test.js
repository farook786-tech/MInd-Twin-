'use strict';

/**
 * Watermark / once-only logic of the listener-based trigger runner, with fake
 * snapshots, fake timers and an in-memory state store.
 */

const { createTriggerRunner, versionOf } = require('../src/firebase/triggerRunner');
const { createMemoryStateStore } = require('../src/firebase/runnerState');

const quietLogger = { info: () => {}, warn: jest.fn(), error: jest.fn() };

function ts(ms) {
  const seconds = Math.floor(ms / 1000);
  return { seconds, nanoseconds: (ms % 1000) * 1e6, toMillis: () => ms };
}
const Timestamp = { fromMillis: (ms) => ts(ms) };

function doc(path, { created, updated = created, data = {} }) {
  return {
    id: path.split('/').pop(),
    ref: { path },
    createTime: ts(created),
    updateTime: ts(updated),
    data: () => data,
  };
}
const added = (d) => ({ type: 'added', doc: d });
const modified = (d) => ({ type: 'modified', doc: d });
const snapshot = (readTime, changes) => ({ readTime: ts(readTime), docChanges: () => changes });

/** Fake query source: records subscriptions so tests can push snapshots / errors. */
function fakeSource() {
  const subs = [];
  return {
    subs,
    query: (_db, since) => ({
      onSnapshot(next, error) {
        const sub = { next, error, since: since.toMillis(), active: true };
        subs.push(sub);
        return () => { sub.active = false; };
      },
    }),
    get current() { return subs[subs.length - 1]; },
  };
}

function manualTimers() {
  const list = [];
  return {
    list,
    setTimer: (fn, ms) => {
      const h = { fn, ms, cancelled: false };
      list.push(h);
      return h;
    },
    clearTimer: (h) => { if (h) h.cancelled = true; },
    /** Fires every pending timer whose delay <= maxMs (not the periodic ones). */
    fire(filter = () => true) {
      const due = list.filter((h) => !h.cancelled && !h.fired && filter(h));
      for (const h of due) {
        h.fired = true;
        h.fn();
      }
      return due.length;
    },
  };
}

const MIN = 60 * 1000;
const NOW = 1_700_000_000_000;

function makeRunner({ store, handle, kind = 'create', now = () => NOW, options = {}, source = fakeSource(), timers = manualTimers(), extraSpecs = [] }) {
  const runner = createTriggerRunner({
    db: {},
    Timestamp,
    specs: [{ name: 'col', kind, query: source.query, handle }, ...extraSpecs],
    stateStore: store,
    logger: quietLogger,
    now,
    setTimer: timers.setTimer,
    clearTimer: timers.clearTimer,
    options: { overlapMs: 2 * MIN, initialLookbackMs: 15 * MIN, flushMs: 30 * 1000, resubscribeMs: 0, querySlackMs: 0, ...options },
  });
  return { runner, source, timers };
}

describe('trigger runner: watermark and once-only processing', () => {
  test('first start: only docs newer than the lookback are processed; redelivery is ignored', async () => {
    const store = createMemoryStateStore();
    const handled = [];
    const { runner, source } = makeRunner({ store, handle: async ({ doc: d }) => handled.push(d.id) });
    await runner.start();
    // Query bounded at watermark - overlap (lookback 15 min, overlap 2 min).
    expect(source.current.since).toBe(NOW - 17 * MIN);
    source.current.next(snapshot(NOW, [
      added(doc('col/old', { created: NOW - 60 * MIN })), // history
      added(doc('col/recent', { created: NOW - 5 * MIN })),
    ]));
    await runner.idle();
    expect(handled).toEqual(['recent']);
    // Re-delivery of the same doc (reconnect) is not re-processed.
    source.current.next(snapshot(NOW + 1000, [added(doc('col/recent', { created: NOW - 5 * MIN }))]));
    await runner.idle();
    expect(handled).toEqual(['recent']);
    expect(runner.status().listeners[0].watermark).toBe(new Date(NOW + 1000).toISOString());
  });

  test('restart with persisted state: no reprocessing, changes made while down are processed', async () => {
    const store = createMemoryStateStore();
    const handled = [];
    const handle = async ({ doc: d }) => handled.push(d.id);
    const a = makeRunner({ store, handle });
    await a.runner.start();
    a.source.current.next(snapshot(NOW, [added(doc('col/a', { created: NOW - 1000 }))]));
    await a.runner.idle();
    await a.runner.stop(); // flushes state
    expect(store.peek().listeners.col.watermark).toBe(NOW);
    expect(store.peek().listeners.col.recent).toEqual([`${NOW - 1000}|col/a`]);

    const later = NOW + 60 * MIN;
    const b = makeRunner({ store, handle, now: () => later });
    await b.runner.start();
    // Resumes from the saved watermark (minus overlap), not from "now".
    expect(b.source.current.since).toBe(NOW - 2 * MIN);
    b.source.current.next(snapshot(later, [
      added(doc('col/a', { created: NOW - 1000 })), // processed before restart
      added(doc('col/b', { created: NOW + 10 * MIN })), // written while down
    ]));
    await b.runner.idle();
    expect(handled).toEqual(['a', 'b']);
  });

  test('overlap window re-checks late docs just behind the watermark', async () => {
    const store = createMemoryStateStore({ version: 1, listeners: { col: { watermark: NOW, recent: [] } } });
    const handled = [];
    const { runner, source } = makeRunner({ store, handle: async ({ doc: d }) => handled.push(d.id) });
    await runner.start();
    source.current.next(snapshot(NOW + 5000, [
      added(doc('col/late', { created: NOW - 30 * 1000 })), // inside overlap, not in recent
      added(doc('col/tooOld', { created: NOW - 3 * MIN })), // outside overlap
    ]));
    await runner.idle();
    expect(handled).toEqual(['late']);
  });

  test('maximum catch-up clamps a very old watermark', async () => {
    const store = createMemoryStateStore({ version: 1, listeners: { col: { watermark: NOW - 10 * 24 * 60 * MIN, recent: [] } } });
    const { runner, source } = makeRunner({ store, handle: async () => {}, options: { maxCatchupMs: 24 * 60 * MIN } });
    await runner.start();
    expect(source.current.since).toBe(NOW - 24 * 60 * MIN - 2 * MIN);
  });

  test('create kind ignores modifications; processes each doc once', async () => {
    const store = createMemoryStateStore();
    const handled = [];
    const { runner, source } = makeRunner({ store, handle: async ({ doc: d }) => handled.push(d.id) });
    await runner.start();
    const d1 = doc('col/x', { created: NOW });
    source.current.next(snapshot(NOW + 1, [added(d1)]));
    source.current.next(snapshot(NOW + 2, [modified(doc('col/x', { created: NOW, updated: NOW + 2 }))]));
    await runner.idle();
    expect(handled).toEqual(['x']);
  });

  test('write kind: once per version, with the previous version as `before`', async () => {
    const store = createMemoryStateStore();
    const seen = [];
    const { runner, source } = makeRunner({
      store, kind: 'write',
      handle: async ({ doc: d, before }) => seen.push({ v: d.data().v, before: before && before.v }),
    });
    await runner.start();
    source.current.next(snapshot(NOW + 1, [added(doc('col/a', { created: NOW, data: { v: 1 } }))]));
    source.current.next(snapshot(NOW + 3, [modified(doc('col/a', { created: NOW, updated: NOW + 2, data: { v: 2 } }))]));
    // the same version re-delivered (e.g. after resubscribe) is skipped
    source.current.next(snapshot(NOW + 4, [added(doc('col/a', { created: NOW, updated: NOW + 2, data: { v: 2 } }))]));
    await runner.idle();
    expect(seen).toEqual([{ v: 1, before: null }, { v: 2, before: 1 }]);
  });

  test('handler failure: retried with backoff; watermark held behind it until it succeeds', async () => {
    const store = createMemoryStateStore();
    let failures = 2;
    const handled = [];
    const timers = manualTimers();
    const { runner, source } = makeRunner({
      store, timers,
      handle: async ({ doc: d }) => {
        if (d.id === 'flaky' && failures > 0) {
          failures -= 1;
          throw new Error('transient');
        }
        handled.push(d.id);
      },
    });
    await runner.start();
    source.current.next(snapshot(NOW + 10, [
      added(doc('col/flaky', { created: NOW + 1 })),
      added(doc('col/next', { created: NOW + 2 })), // not blocked by the failure
    ]));
    await runner.idle();
    expect(handled).toEqual(['next']);
    let st = runner.status().listeners[0];
    expect(st.pendingRetries).toBe(1);
    expect(st.watermark).toBe(new Date(NOW).toISOString()); // flaky.createTime - 1
    const retryDelays = () => timers.list.filter((h) => !h.fired && !h.cancelled && h.ms !== 30000).map((h) => h.ms);
    expect(retryDelays()).toEqual([1000]);
    timers.fire((h) => h.ms !== 30000);
    await runner.idle();
    expect(retryDelays()).toEqual([2000]); // exponential backoff
    timers.fire((h) => h.ms !== 30000);
    await runner.idle();
    expect(handled).toEqual(['next', 'flaky']);
    st = runner.status().listeners[0];
    expect(st.pendingRetries).toBe(0);
    expect(st.watermark).toBe(new Date(NOW + 10).toISOString());
  });

  test('a change still failing at shutdown is retried after restart', async () => {
    const store = createMemoryStateStore();
    const a = makeRunner({ store, handle: async () => { throw new Error('down'); } });
    await a.runner.start();
    a.source.current.next(snapshot(NOW + 10, [added(doc('col/f', { created: NOW + 5 }))]));
    await a.runner.idle();
    await a.runner.stop();
    // held just below the failing change (createTime - 1), not at the readTime
    expect(store.peek().listeners.col.watermark).toBe(NOW + 4);
    const handled = [];
    const b = makeRunner({ store, handle: async ({ doc: d }) => handled.push(d.id), now: () => NOW + MIN });
    await b.runner.start();
    b.source.current.next(snapshot(NOW + MIN, [added(doc('col/f', { created: NOW + 5 }))]));
    await b.runner.idle();
    expect(handled).toEqual(['f']);
  });

  test('listener error: resubscribes with exponential backoff and a recomputed bound', async () => {
    const store = createMemoryStateStore();
    const timers = manualTimers();
    const { runner, source } = makeRunner({ store, timers, handle: async () => {} });
    await runner.start();
    source.current.next(snapshot(NOW + 5 * MIN, []));
    await runner.idle();
    const first = source.current;
    first.error(Object.assign(new Error('UNAVAILABLE'), { code: 14 }));
    expect(first.active).toBe(false);
    const delays = () => timers.list.filter((h) => !h.fired && !h.cancelled && h.ms !== 30000).map((h) => h.ms);
    expect(delays()).toEqual([1000]);
    timers.fire((h) => h.ms === 1000);
    await runner.idle();
    expect(source.subs).toHaveLength(2);
    expect(source.current.since).toBe(NOW + 5 * MIN - 2 * MIN); // from the advanced watermark
    source.current.error(new Error('again'));
    expect(delays()).toEqual([2000]);
    timers.fire((h) => h.ms === 2000);
    await runner.idle();
    expect(source.subs).toHaveLength(3);
    expect(runner.status().listeners[0].errors).toBe(2);
    // a successful snapshot resets the backoff
    source.current.next(snapshot(NOW + 6 * MIN, []));
    await runner.idle();
    source.current.error(new Error('third'));
    expect(delays()).toEqual([1000]);
  });

  test('each listener processes serially; global concurrency is bounded', async () => {
    const store = createMemoryStateStore();
    let active = 0;
    let maxActive = 0;
    let perColActive = 0;
    let perColMax = 0;
    const gate = [];
    const handle = async () => {
      active += 1;
      perColActive += 1;
      maxActive = Math.max(maxActive, active);
      perColMax = Math.max(perColMax, perColActive);
      await new Promise((r) => gate.push(r));
      active -= 1;
      perColActive -= 1;
    };
    const others = [1, 2, 3].map((i) => {
      const src = fakeSource();
      return { src, spec: { name: `o${i}`, kind: 'create', query: src.query, handle: async () => {
        active += 1;
        maxActive = Math.max(maxActive, active);
        await new Promise((r) => gate.push(r));
        active -= 1;
      } } };
    });
    const { runner, source } = makeRunner({
      store, handle, options: { concurrency: 2 }, extraSpecs: others.map((o) => o.spec),
    });
    await runner.start();
    source.current.next(snapshot(NOW + 9, [1, 2, 3].map((i) => added(doc(`col/d${i}`, { created: NOW + i })))));
    for (const o of others) o.src.current.next(snapshot(NOW + 9, [added(doc(`${o.spec.name}/z`, { created: NOW + 1 }))]));
    for (let i = 0; i < 50; i += 1) {
      await new Promise((r) => setImmediate(r));
      const g = gate.shift();
      if (g) g();
    }
    await runner.idle();
    expect(perColMax).toBe(1);
    expect(maxActive).toBeLessThanOrEqual(2);
    expect(runner.status().listeners.reduce((n, l) => n + l.processed, 0)).toBe(6);
  });

  test('state flush is debounced and survives a failing store', async () => {
    let fail = true;
    const saved = [];
    const store = {
      load: async () => null,
      save: async (s) => {
        if (fail) throw new Error('quota');
        saved.push(s);
      },
    };
    const timers = manualTimers();
    const { runner, source } = makeRunner({ store, timers, handle: async () => {} });
    await runner.start();
    source.current.next(snapshot(NOW + 1, [added(doc('col/a', { created: NOW }))]));
    await runner.idle();
    expect(saved).toHaveLength(0); // nothing written until the flush timer fires
    timers.fire((h) => h.ms === 30000);
    await new Promise((r) => setImmediate(r));
    expect(saved).toHaveLength(0);
    fail = false;
    await runner.flush(); // still dirty after the failed attempt
    expect(saved).toHaveLength(1);
    expect(saved[0].listeners.col.watermark).toBe(NOW + 1);
  });

  test('versionOf is exact and sortable', () => {
    const a = versionOf({ seconds: 9, nanoseconds: 5 });
    const b = versionOf({ seconds: 10, nanoseconds: 0 });
    const c = versionOf({ seconds: 10, nanoseconds: 1 });
    expect(a < b && b < c).toBe(true);
  });
});
