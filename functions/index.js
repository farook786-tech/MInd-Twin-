'use strict';

/**
 * MindTwin Cloud Functions entry point. Contract: docs/DATA_MODEL.md.
 */

const { setGlobalOptions } = require('firebase-functions/v2');
const { REGION } = require('./src/logic/constants');

setGlobalOptions({ region: REGION });

const callables = require('./src/callables');
const clinical = require('./src/triggers/clinical');
const notifications = require('./src/triggers/notifications');

// Callables
exports.registerPatient = callables.registerPatient;
exports.registerTherapist = callables.registerTherapist;
exports.joinTherapist = callables.joinTherapist;
exports.approveTherapist = callables.approveTherapist;
exports.getMyInviteCode = callables.getMyInviteCode;

// Firestore triggers
exports.onVitalCreated = clinical.onVitalCreated;
exports.onDailyLogCreated = clinical.onDailyLogCreated;
exports.onDailyLogUpdated = clinical.onDailyLogUpdated;
exports.onAssessmentCreated = clinical.onAssessmentCreated;
exports.onCrisisEventCreated = notifications.onCrisisEventCreated;
exports.onMessageCreated = notifications.onMessageCreated;
exports.onAppointmentWritten = notifications.onAppointmentWritten;

// Auth triggers
exports.onAuthUserDeleted = require('./src/triggers/accounts').onAuthUserDeleted;
