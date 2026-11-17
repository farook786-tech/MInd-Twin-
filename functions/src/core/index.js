'use strict';

/**
 * Shared core of MindTwin's server-side logic.
 *
 * Dependency free on purpose: only node built-ins and ../logic/*. Firebase
 * SDK objects are injected (see ./deps.js), so the backend can `require()`
 * this directory by relative path without installing functions/node_modules.
 */

const { checkDeps } = require('./deps');
const { createPush } = require('./push');
const { createCallables, runCallable, CALLABLE_NAMES } = require('./callables');
const { createTriggers } = require('./triggers');
const { createInviteCodes } = require('./inviteCodes');
const errors = require('./errors');

/**
 * @param {import('./deps').CoreDeps} deps
 */
function createCore(deps) {
  checkDeps(deps);
  const push = createPush(deps);
  return {
    push,
    callables: createCallables(deps),
    triggers: createTriggers(deps, push),
    inviteCodes: createInviteCodes(deps),
    deps,
  };
}

module.exports = { createCore, runCallable, CALLABLE_NAMES, errors };
