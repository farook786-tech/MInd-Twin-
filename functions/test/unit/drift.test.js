'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const d = require('../../src/logic/drift');

const NOW = Date.UTC(2026, 10, 17, 12, 0, 0);
const snap = (level, index = 60) => ({ level, index });

test('notifies only on a transition into drifting', () => {
  assert.equal(d.shouldNotifyDrift(snap('watch', 40), snap('drifting'), null, NOW), true);
  assert.equal(d.shouldNotifyDrift(undefined, snap('drifting'), null, NOW), true);
  assert.equal(d.shouldNotifyDrift(snap('drifting'), snap('drifting', 70), null, NOW), false);
  assert.equal(d.shouldNotifyDrift(snap('stable', 5), snap('watch', 30), null, NOW), false);
  assert.equal(d.shouldNotifyDrift(snap('drifting'), snap('stable', 10), null, NOW), false);
});

test('3-day per-patient cooldown', () => {
  const day = 24 * 60 * 60 * 1000;
  assert.equal(d.shouldNotifyDrift(snap('watch'), snap('drifting'), NOW - day, NOW), false);
  assert.equal(d.shouldNotifyDrift(snap('watch'), snap('drifting'), NOW - 3 * day, NOW), true);
  // a clock in the future does not suppress forever
  assert.equal(d.shouldNotifyDrift(snap('watch'), snap('drifting'), NOW + day, NOW), true);
});

test('invalid snapshots never notify', () => {
  assert.equal(d.shouldNotifyDrift(null, { level: 'DRIFTING' }, null, NOW), false);
  assert.equal(d.shouldNotifyDrift(null, { level: 'drifting', index: 140 }, null, NOW), false);
  assert.equal(d.shouldNotifyDrift(null, 'drifting', null, NOW), false);
  assert.deepEqual(d.parseDriftSnapshot({ level: 'learning', index: null }), { level: 'learning', index: null });
});

test('payload is low priority and explicitly non-diagnostic', () => {
  const p = d.describeDriftNotification('Pat', snap('drifting', 62));
  assert.equal(p.priority, 'normal');
  assert.equal(p.data.type, 'drift');
  assert.match(p.body, /not diagnostic/);
  assert.match(p.body, /62\/100/);
  assert.doesNotMatch(p.title + p.body, /risk|crisis|danger/i);
});
