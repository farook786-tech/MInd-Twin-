# MindTwin Cloud Functions

Server side of the data contract in `docs/DATA_MODEL.md`: roles (custom
claims), therapist linking, clinical threshold checks, push notifications and
meeting links. Project: `mindtwin-60879`, region `us-central1`, runtime Node 22.

## What is deployed

| Function | Kind | Purpose |
|---|---|---|
| `registerPatient` | callable | `{name, inviteCode}` → links patient, claim `role=patient` |
| `registerTherapist` | callable | `{name, licenseNumber?, specialty?}` → claim `therapist_pending` |
| `joinTherapist` | callable | patient switches therapist; re-stamps `therapistId` on the patient's `daily_logs`, `clinical_assessments`, `crisis_events`, `vitals`, `journal_entries` |
| `approveTherapist` | callable | admin only (`admin: true` claim) → claim `therapist`, invite code |
| `getMyInviteCode` | callable | approved therapist; creates a code if missing |
| `onVitalCreated` | trigger | `users/{pid}.latestVitals`, thresholds (HR > 120 / < 45 bpm, sleep < 4 h, per-patient `vitalThresholds`), 30-min cooldown per patient+type+direction in `alert_cooldowns/{pid}`; HR ≤ 0 or > 300 is logged as a sensor error |
| `onDailyLogCreated` / `onDailyLogUpdated` | trigger | `riskScore` (or merged `mlRisk.riskScore`) ≥ 75 → `high_risk` |
| `onAssessmentCreated` | trigger | PHQ-9 item 9 > 0 → critical; total ≥ 20 → `phq9_severe` |
| `onCrisisEventCreated` | trigger | high-priority push to the therapist (`clinical_critical`) |
| `onMessageCreated` | trigger | push to receiver (`chat_messages`, message text is not included) |
| `onAppointmentWritten` | trigger | sets `meetingUrl` once, pushes the other party (`appointments`), flags double bookings (`conflict`, `conflictWith`) |

Each trigger can safely run more than once. Crisis docs use ids derived from
the source doc (`vital_<id>`, `dailylog_<id>`, `assessment_<id>`), and every
push is guarded by a `push_receipts/{key}` doc. Triggers run with `retry: true`.
Server-only collections (`alert_cooldowns`, `push_receipts`, `invite_codes`)
cannot be reached by any client.

## Prerequisites

* The Firebase project must be on the **Blaze (pay-as-you-go)** plan. Cloud
  Functions v2 and outbound FCM need it.
* Firebase CLI ≥ 13 (`npm i -g firebase-tools`), logged in as a project owner:
  `firebase login`.
* Node 22 locally.

## Test locally

```bash
cd functions && npm ci && npm run lint && npm test        # unit tests (pure logic)
cd ../test/rules && npm ci && npm run test:emulator        # security-rules tests (Java 11+ required)
cd ../../functions && npm run test:smoke                   # end-to-end on auth+firestore+functions emulators
```

On Windows, if Java is not on PATH, set
`JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"`. If the functions
emulator reports "Timeout after 10000", set `FUNCTIONS_DISCOVERY_TIMEOUT=120`.

## Deploy

```bash
firebase use mindtwin-60879
firebase deploy --only firestore:rules,firestore:indexes,functions
```

`predeploy` runs lint and the unit tests. Composite indexes can take several
minutes to build, and queries that need them fail until the build finishes.

**Order matters.** Deploying these rules locks out every account that has no
`role` claim. Before you deploy:

1. Ship app builds that call `registerPatient` / `registerTherapist`.
2. Backfill claims for existing users: `node scripts/backfill-claims.js` (dry run),
   then `--apply`. It never promotes anyone to `therapist`; run
   `approve-therapist.js` for each legitimate therapist. Patients whose
   `therapistId` is not an approved therapist are listed and must re-link
   with an invite code.
3. Then deploy the rules.

## Admin operations

The scripts load `firebase-admin` from `functions/node_modules`, so run
`npm ci` in `functions/` first. The service-account key is read from
`GOOGLE_APPLICATION_CREDENTIALS` and is never printed.

```bash
export GOOGLE_APPLICATION_CREDENTIALS=backend/config/firebase-service-account.json
node scripts/make-admin.js admin@clinic.example            # grant admin claim (--revoke to remove)
node scripts/approve-therapist.js therapist@clinic.example # approve + print invite code
```

Users have to refresh their ID token after any claim change. The apps do this
with `getIdTokenResult(true)`.

## Monitoring

Watch the logs for `CRISIS EVENT FOR PATIENT WITHOUT THERAPIST`,
`CRISIS EVENT HAS NO THERAPIST`, `no FCM tokens registered` (severity ERROR on
`clinical_critical`) and `push delivered to no device`. Each one means a crisis
alert reached no clinician. Set up a log-based alert on them.
