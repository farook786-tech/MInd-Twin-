'use strict';

/**
 * Builds the shared core (./core) with THIS package's firebase-admin and the
 * Cloud Functions logger. Lazily, so loading a module does not touch the SDK.
 */

const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { logger } = require('firebase-functions/v2');
const { db, auth, messaging } = require('./admin');
const { createCore } = require('./core');

let instance = null;

function core() {
  if (!instance) {
    instance = createCore({ db, auth, messaging, FieldValue, Timestamp, logger });
  }
  return instance;
}

module.exports = { core, logger };
