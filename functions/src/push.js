'use strict';

/**
 * Push helpers bound to this package's firebase-admin. Implementation:
 * ./core/push.js (shared with the backend runner).
 */

const { core } = require('./runtime');
const { stringifyData } = require('./core/push');

function sendPushToUser(params) {
  return core().push.sendPushToUser(params);
}

module.exports = { sendPushToUser, stringifyData };
