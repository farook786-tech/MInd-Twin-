'use strict';

/**
 * Pure logic for an OPTIONAL low-priority therapist notification when a patient's
 * Digital Twin drift (lib/services/digital_twin_service.dart) becomes `drifting`.
 * Not wired to any trigger yet (see docs/DATA_MODEL.md "Digital Twin drift").
 *
 * The drift index is an early-warning, personal-baseline signal — NOT diagnostic.
 * It never creates a crisis_event and never uses the clinical_critical channel.
 */

const DRIFT_LEVELS = Object.freeze(['learning', 'stable', 'watch', 'drifting']);

// At most one drift notification per patient per 3 days.
const DRIFT_NOTIFY_COOLDOWN_MS = 3 * 24 * 60 * 60 * 1000;

function isFiniteNumber(v) {
  return typeof v === 'number' && Number.isFinite(v);
}

/**
 * Validates a `{level, index, at}` drift snapshot (as the patient app would write it).
 * @param {unknown} s
 * @return {{level:string, index:number|null}|null}
 */
function parseDriftSnapshot(s) {
  if (!s || typeof s !== 'object' || Array.isArray(s)) return null;
  if (!DRIFT_LEVELS.includes(s.level)) return null;
  const index = s.index === null || s.index === undefined ? null : s.index;
  if (index !== null && !(isFiniteNumber(index) && index >= 0 && index <= 100)) return null;
  return { level: s.level, index };
}

/**
 * True only on a transition INTO `drifting` (not while it stays drifting), outside
 * the per-patient cooldown. Invalid / missing snapshots never notify.
 * @param {unknown} before previous snapshot (or undefined)
 * @param {unknown} after new snapshot
 * @param {number|null} lastNotifiedMillis
 * @param {number} nowMillis
 * @return {boolean}
 */
function shouldNotifyDrift(before, after, lastNotifiedMillis, nowMillis) {
  const a = parseDriftSnapshot(after);
  if (!a || a.level !== 'drifting') return false;
  const b = parseDriftSnapshot(before);
  if (b && b.level === 'drifting') return false;
  if (isFiniteNumber(lastNotifiedMillis) &&
      nowMillis >= lastNotifiedMillis &&
      nowMillis - lastNotifiedMillis < DRIFT_NOTIFY_COOLDOWN_MS) {
    return false;
  }
  return true;
}

/**
 * Low-priority push payload (Android channel `appointments`-level importance, NOT
 * `clinical_critical`). Wording is explicitly non-diagnostic.
 * @param {string} patientName
 * @param {{index:number|null}} snapshot
 * @return {{title:string, body:string, priority:'normal', data:{type:string}}}
 */
function describeDriftNotification(patientName, snapshot) {
  const name = patientName || 'A patient';
  const idx = snapshot && isFiniteNumber(snapshot.index) ? ` (${snapshot.index}/100)` : '';
  return {
    title: `Pattern change: ${name}`,
    body: `${name}'s recent days differ from their personal baseline${idx}. ` +
      'Early-warning signal, not diagnostic — review when convenient.',
    priority: 'normal',
    data: { type: 'drift' },
  };
}

module.exports = {
  DRIFT_LEVELS,
  DRIFT_NOTIFY_COOLDOWN_MS,
  parseDriftSnapshot,
  shouldNotifyDrift,
  describeDriftNotification,
};
