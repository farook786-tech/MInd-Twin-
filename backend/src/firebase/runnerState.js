'use strict';

/**
 * Persistence of the trigger runner's watermarks (see triggerRunner.js).
 * Stored in a server-only Firestore doc `_runner/{instanceId}` (no client
 * access: default-deny in firestore.rules), so it survives Render restarts
 * whose filesystem is ephemeral. One doc per backend instance: the laptop and
 * a Render instance each track their own progress.
 */

const RUNNER_STATE_COLLECTION = '_runner';

function createFirestoreStateStore({ db, FieldValue, instanceId }) {
  const ref = () => db().collection(RUNNER_STATE_COLLECTION).doc(instanceId);
  return {
    async load() {
      const snap = await ref().get();
      return snap.exists ? snap.data() : null;
    },
    async save(state) {
      await ref().set({ ...state, instanceId, savedAt: FieldValue.serverTimestamp() });
    },
  };
}

/** In-memory store (tests). */
function createMemoryStateStore(initial = null) {
  let value = initial ? JSON.parse(JSON.stringify(initial)) : null;
  return {
    saves: 0,
    async load() {
      return value ? JSON.parse(JSON.stringify(value)) : null;
    },
    async save(state) {
      this.saves += 1;
      value = JSON.parse(JSON.stringify(state));
    },
    peek() {
      return value;
    },
  };
}

module.exports = { createFirestoreStateStore, createMemoryStateStore, RUNNER_STATE_COLLECTION };
