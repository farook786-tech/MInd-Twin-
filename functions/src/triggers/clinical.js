'use strict';

/**
 * Cloud Functions (Blaze) wrappers for the clinical triggers. Logic lives in
 * ../core/triggers.js and is shared with the backend runner (Spark plan).
 */

const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { COLLECTIONS } = require('../logic/constants');
const { core } = require('../runtime');
const { eventCtx } = require('./eventContext');

const TRIGGER_OPTS = { retry: true };

/** vitals/{vitalId} created: latestVitals snapshot + threshold alert. */
const onVitalCreated = onDocumentCreated(
  { document: `${COLLECTIONS.VITALS}/{vitalId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    await core().triggers.vitalCreated(event.data, eventCtx(event));
  });

/** daily_logs/{logId} created: riskScore >= 75 => high_risk crisis. */
const onDailyLogCreated = onDocumentCreated(
  { document: `${COLLECTIONS.DAILY_LOGS}/{logId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    await core().triggers.dailyLogCreated(event.data, eventCtx(event));
  });

/**
 * daily_logs/{logId} updated (ML results merged after create). Same
 * deterministic crisis id => no duplicate. Additive safety net.
 */
const onDailyLogUpdated = onDocumentUpdated(
  { document: `${COLLECTIONS.DAILY_LOGS}/{logId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    await core().triggers.dailyLogUpdated(event.data, eventCtx(event));
  });

/** clinical_assessments/{assessmentId} created: PHQ-9 >= 20, item 9 > 0, risk >= 75. */
const onAssessmentCreated = onDocumentCreated(
  { document: `${COLLECTIONS.ASSESSMENTS}/{assessmentId}`, ...TRIGGER_OPTS },
  async (event) => {
    if (!event.data) return;
    await core().triggers.assessmentCreated(event.data, eventCtx(event));
  });

module.exports = {
  onVitalCreated,
  onDailyLogCreated,
  onDailyLogUpdated,
  onAssessmentCreated,
  createOrMergeCrisis: (...args) => core().triggers.createOrMergeCrisis(...args),
};
