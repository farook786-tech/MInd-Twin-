'use strict';

const ALWAYS_PRUNE = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);
const TRANSIENT = new Set([
  'messaging/internal-error',
  'messaging/server-unavailable',
  'messaging/unavailable',
  'messaging/quota-exceeded',
  'messaging/message-rate-exceeded',
  'messaging/device-message-rate-exceeded',
]);

/**
 * Classifies per-token FCM results.
 * `messaging/invalid-argument` can mean a bad token OR a bad payload. It is
 * pruned only when another token in the same request succeeded (so the
 * payload is known to be valid); otherwise pruning could wipe every device of
 * a therapist because of a payload bug.
 * @param {string[]} tokens
 * @param {Array<{success: boolean, error?: {code: string, message: string}}>} responses
 * @return {{prune: string[], transient: boolean, otherErrors: Array<{code:string,message:string}>}}
 */
function classifySendErrors(tokens, responses) {
  const anySuccess = responses.some((r) => r.success);
  const prune = [];
  const otherErrors = [];
  let transient = false;
  responses.forEach((r, i) => {
    if (r.success) return;
    const code = (r.error && r.error.code) || 'unknown';
    if (ALWAYS_PRUNE.has(code) || (code === 'messaging/invalid-argument' && anySuccess)) {
      prune.push(tokens[i]);
    } else if (TRANSIENT.has(code)) {
      transient = true;
    } else {
      otherErrors.push({ code, message: (r.error && r.error.message) || '' });
    }
  });
  return { prune, transient, otherErrors };
}

module.exports = { classifySendErrors };
