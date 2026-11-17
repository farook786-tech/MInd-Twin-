'use strict';

/**
 * Invite-code operations bound to this package's firebase-admin. Used by the
 * callables and by scripts/approve-therapist.js (which loads this module from
 * functions/). The implementation lives in ./core/inviteCodes.js so the
 * backend runner can share it with its own firebase-admin instance.
 */

const { FieldValue } = require('firebase-admin/firestore');
const { createInviteCodes } = require('./core/inviteCodes');
const { InviteCodeError } = require('./core/errors');

const { ensureInviteCode, resolveInviteCode, approveTherapistAccount } =
  createInviteCodes({ FieldValue });

module.exports = {
  InviteCodeError,
  ensureInviteCode,
  resolveInviteCode,
  approveTherapistAccount,
};
