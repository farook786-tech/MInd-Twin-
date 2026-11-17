'use strict';

/** Converts a firebase-functions v2 CloudEvent into the core handler ctx. */
function eventCtx(event) {
  const t = Date.parse(event.time);
  return {
    params: event.params || {},
    eventId: event.id,
    eventTime: Number.isFinite(t) ? t : undefined,
  };
}

module.exports = { eventCtx };
