'use strict';

/**
 * Pure vital-sign logic (no Firebase imports) so it is unit-testable.
 */

const { VITAL_ALERT_COOLDOWN_MS } = require('./constants');

const DEFAULT_THRESHOLDS = Object.freeze({
  heartRateHigh: 120,
  heartRateLow: 45,
  sleepHoursLow: 4,
});

// A therapist override outside these bounds is rejected (defaults are used
// instead) so a typo such as heartRateHigh: 1200 cannot silence alerts.
const THRESHOLD_BOUNDS = Object.freeze({
  heartRateHigh: [80, 220],
  heartRateLow: [25, 80],
  sleepHoursLow: [0, 12],
});

const VITAL_SPECS = Object.freeze({
  heart_rate: { unit: 'bpm', snapshotKey: 'heartRate' },
  sleep: { unit: 'hours', snapshotKey: 'sleepHours' },
  steps: { unit: 'count', snapshotKey: 'steps' },
});

// Heart-rate values at or beyond these are escalated to `critical`.
const HR_CRITICAL_HIGH = 150;
const HR_CRITICAL_LOW = 40;

function isFiniteNumber(v) {
  return typeof v === 'number' && Number.isFinite(v);
}

/**
 * Merges a per-patient override with the defaults, field by field.
 * @param {unknown} override users/{pid}.vitalThresholds
 * @return {{thresholds: {heartRateHigh:number, heartRateLow:number,
 *   sleepHoursLow:number}, warnings: string[]}}
 */
function resolveThresholds(override) {
  const thresholds = { ...DEFAULT_THRESHOLDS };
  const warnings = [];
  if (override !== undefined && override !== null) {
    if (typeof override !== 'object' || Array.isArray(override)) {
      warnings.push('vitalThresholds is not a map; using defaults');
    } else {
      for (const key of Object.keys(DEFAULT_THRESHOLDS)) {
        if (!(key in override)) continue;
        const value = override[key];
        const [min, max] = THRESHOLD_BOUNDS[key];
        if (isFiniteNumber(value) && value >= min && value <= max) {
          thresholds[key] = value;
        } else {
          warnings.push(`vitalThresholds.${key}=${JSON.stringify(value)} ` +
            `out of bounds [${min}, ${max}]; using default ${DEFAULT_THRESHOLDS[key]}`);
        }
      }
    }
  }
  if (thresholds.heartRateLow >= thresholds.heartRateHigh) {
    warnings.push('heartRateLow >= heartRateHigh; using default heart-rate thresholds');
    thresholds.heartRateHigh = DEFAULT_THRESHOLDS.heartRateHigh;
    thresholds.heartRateLow = DEFAULT_THRESHOLDS.heartRateLow;
  }
  return { thresholds, warnings };
}

/**
 * Converts a Firestore Timestamp / Date / millis into epoch millis or null.
 * @param {unknown} t
 * @return {number|null}
 */
function toMillis(t) {
  if (t === null || t === undefined) return null;
  if (typeof t.toMillis === 'function') return t.toMillis();
  if (t instanceof Date) return t.getTime();
  if (isFiniteNumber(t)) return t;
  return null;
}

/**
 * Validates a vitals document.
 * @param {object} data
 * @return {{ok: true, reading: {patientId:string, type:string, value:number,
 *   unit:string, measuredAtMillis:number}} |
 *   {ok: false, sensorError: boolean, reason: string}}
 */
function validateVitalReading(data) {
  if (!data || typeof data !== 'object') {
    return { ok: false, sensorError: false, reason: 'empty document' };
  }
  const { patientId, type, value, unit } = data;
  if (typeof patientId !== 'string' || patientId.length === 0) {
    return { ok: false, sensorError: false, reason: 'missing patientId' };
  }
  const spec = VITAL_SPECS[type];
  if (!spec) {
    return { ok: false, sensorError: false, reason: `unknown type ${JSON.stringify(type)}` };
  }
  if (unit !== spec.unit) {
    return { ok: false, sensorError: false, reason: `unit ${JSON.stringify(unit)} != ${spec.unit}` };
  }
  if (!isFiniteNumber(value)) {
    return { ok: false, sensorError: true, reason: `non-numeric value ${JSON.stringify(value)}` };
  }
  const measuredAtMillis = toMillis(data.measuredAt);
  if (measuredAtMillis === null) {
    return { ok: false, sensorError: false, reason: 'missing measuredAt' };
  }
  // Clearly non-physical values are sensor errors: never alert on them.
  if (type === 'heart_rate' && (value <= 0 || value > 300)) {
    return { ok: false, sensorError: true, reason: `non-physical heart rate ${value} bpm` };
  }
  if (type === 'sleep' && (value < 0 || value > 24)) {
    return { ok: false, sensorError: true, reason: `non-physical sleep ${value} h` };
  }
  if (type === 'steps' && (value < 0 || value > 200000)) {
    return { ok: false, sensorError: true, reason: `non-physical steps ${value}` };
  }
  return { ok: true, reading: { patientId, type, value, unit, measuredAtMillis } };
}

/**
 * Decides whether a valid reading breaches a threshold.
 * HR: value > heartRateHigh => vital_high; value < heartRateLow => vital_low.
 * Sleep: value < sleepHoursLow => vital_low. Steps never alert.
 * @param {{type:string, value:number, unit:string}} reading
 * @param {{heartRateHigh:number, heartRateLow:number, sleepHoursLow:number}} t
 * @return {null|{eventType:string, severity:string, threshold:number,
 *   direction:'high'|'low'}}
 */
function evaluateVital(reading, t) {
  const { type, value } = reading;
  if (type === 'heart_rate') {
    if (value > t.heartRateHigh) {
      return {
        eventType: 'vital_high',
        severity: value >= HR_CRITICAL_HIGH ? 'critical' : 'high',
        threshold: t.heartRateHigh,
        direction: 'high',
      };
    }
    if (value < t.heartRateLow) {
      return {
        eventType: 'vital_low',
        severity: value <= HR_CRITICAL_LOW ? 'critical' : 'high',
        threshold: t.heartRateLow,
        direction: 'low',
      };
    }
    return null;
  }
  if (type === 'sleep') {
    if (value < t.sleepHoursLow) {
      return { eventType: 'vital_low', severity: 'medium', threshold: t.sleepHoursLow, direction: 'low' };
    }
    return null;
  }
  return null;
}

/**
 * Cooldown is per patient + vital type + direction, so a low-HR alert is not
 * suppressed by a high-HR alert a few minutes earlier.
 */
function cooldownField(type, eventType) {
  return `${type}__${eventType}`;
}

function isInCooldown(lastAlertMillis, nowMillis, cooldownMs = VITAL_ALERT_COOLDOWN_MS) {
  if (!isFiniteNumber(lastAlertMillis)) return false;
  return nowMillis - lastAlertMillis < cooldownMs && nowMillis >= lastAlertMillis;
}

/** Only move latestVitals forward in time (late/batched syncs arrive out of order). */
function isNewerReading(existingMeasuredAtMillis, newMillis) {
  if (!isFiniteNumber(existingMeasuredAtMillis)) return true;
  return newMillis > existingMeasuredAtMillis;
}

function crisisIdForVital(vitalDocId) {
  return `vital_${vitalDocId}`;
}

const LABELS = { heart_rate: 'Heart rate', sleep: 'Sleep', steps: 'Steps' };

function describeVitalAlert(patientName, reading, evaluation) {
  const label = LABELS[reading.type] || reading.type;
  const name = patientName || 'Patient';
  const cmp = evaluation.direction === 'high' ? 'above' : 'below';
  const title = `${label} ${evaluation.direction === 'high' ? 'high' : 'low'}: ${name}`;
  const message = `${name}'s ${label.toLowerCase()} reading of ${reading.value} ` +
    `${reading.unit} is ${cmp} the threshold of ${evaluation.threshold} ${reading.unit} ` +
    `(measured ${new Date(reading.measuredAtMillis).toISOString()}).`;
  return { title, message };
}

module.exports = {
  DEFAULT_THRESHOLDS,
  THRESHOLD_BOUNDS,
  VITAL_SPECS,
  resolveThresholds,
  toMillis,
  validateVitalReading,
  evaluateVital,
  cooldownField,
  isInCooldown,
  isNewerReading,
  crisisIdForVital,
  describeVitalAlert,
};
