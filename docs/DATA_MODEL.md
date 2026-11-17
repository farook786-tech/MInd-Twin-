# MindTwin data contract (Firestore = single source of truth)

All real-time data lives in Firestore so both apps see it instantly on any
network. Cloud Functions (`functions/`) do everything a client must not be
trusted with: roles, therapist linking, threshold checks, push notifications,
meeting links. The Node backend (`backend/`) is only used for AI chat / ML.

Times: always Firestore `Timestamp` (server time where possible:
`FieldValue.serverTimestamp()`). Never local ISO strings for new fields.

## Roles (Firebase Auth custom claims — the ONLY trusted source)

| claim `role`        | who                                   | set by                         |
|---------------------|---------------------------------------|--------------------------------|
| `patient`           | patient linked to a therapist         | callable `registerPatient`     |
| `therapist_pending` | therapist signed up, awaiting approval| callable `registerTherapist`   |
| `therapist`         | approved therapist                    | `scripts/approve-therapist.js` (admin) / callable `approveTherapist` (claim `admin`) |
| `admin` (bool claim `admin: true`) | clinic administrator   | manual, via script             |

Clients read the role with `FirebaseAuth.instance.currentUser!.getIdTokenResult(true)`
→ `claims['role']`. After any callable that changes claims, the client MUST call
`getIdTokenResult(true)` (force refresh) before reading Firestore again.

## Callable functions (region `us-central1`, `FirebaseFunctions.instance`)

| name | input | output | notes |
|---|---|---|---|
| `registerPatient` | `{name, inviteCode}` | `{therapistId, therapistName}` | validates code, sets claim, writes `users/{uid}` |
| `registerTherapist` | `{name, licenseNumber?, specialty?}` | `{status:'pending'}` | |
| `joinTherapist` | `{inviteCode}` | `{therapistId, therapistName}` | patient switches therapist |
| `approveTherapist` | `{therapistUid}` | `{inviteCode}` | admin only |
| `getMyInviteCode` | `{}` | `{inviteCode}` | approved therapist only; creates one if missing |

Errors are `FirebaseFunctionsException` with codes `invalid-argument`,
`not-found` (bad invite code), `permission-denied`, `failed-precondition`.

Transport (free Spark plan, current apps): `POST <backend>/api/callable/<name>`
with `Authorization: Bearer <Firebase ID token>` and body `{data: {...}}`;
response `{data: result}` or `{error: {code, message}}` with HTTP 400/401/403/
404/412/429/500/503 for `invalid-argument`/`unauthenticated`/`permission-denied`/
`not-found`/`failed-precondition`/`resource-exhausted`/`internal`/`unavailable`.
Same logic and codes as the Cloud Functions (functions/src/core). The
"Function ..." trigger behaviour below is provided by the backend's listener
runner on Spark (docs/FREE_DEPLOYMENT.md).

## Collections

### `users/{uid}`
Server-owned (clients may NOT write): `role`, `therapistId`, `therapistName`,
`status` (`pending|approved` for therapists), `inviteCode`, `createdAt`.
Client-writable by the owner: `name`, `phone`, `photoUrl`, `settings`, and the
patient snapshot fields below. Readable by: owner; the patient's assigned
therapist (`resource.data.therapistId == auth.uid`).

Patient snapshot fields (written by the patient app, read live by the therapist):
`latestRiskScore` (0–100), `latestRiskState`, `latestWellbeingScore` (0–100),
`latestMoodScore`, `lastCheckInAt` (Timestamp),
`latestVitals: { heartRate: {value, measuredAt}, sleepHours: {value, measuredAt}, steps: {value, measuredAt} }`,
`latestPhq9: {total 0-27, severity, at}`, `latestGad7: {total 0-21, severity, at}`,
`latestCssrs: {risk: 'none'|'low'|'moderate'|'high', at}` (both keys required).
The three instrument snapshots drive the therapist roster sort
(`ClinicalScoring.rosterLevel`, lib/services/clinical_scoring.dart).
`latestRiskScore` is the **check-in wellbeing indicator** (self-report heuristic,
early-warning only; never shown as a risk prediction or diagnosis).

Therapist-set thresholds (therapist of that patient may write ONLY this field):
`vitalThresholds: { heartRateHigh: 120, heartRateLow: 45, sleepHoursLow: 4 }` (defaults if absent).

### `therapist_directory/{therapistUid}` — none. Patients link by invite code only.
### `invite_codes/{code}` — server-only (no client access). `{therapistId, active, createdAt}`.

### `fcm_tokens/{token}`
`{uid, platform: 'android'|'ios', app: 'patient'|'therapist', updatedAt}`. Owner
creates/updates/deletes its own docs (`request.resource.data.uid == auth.uid`).
Client registers on login, on `onTokenRefresh`; deletes on logout.

### `vitals/{id}` — written by the patient phone (Dart or native Kotlin)
Base fields: `{patientId, therapistId, type: 'heart_rate'|'sleep'|'steps', value: number,
unit: 'bpm'|'hours'|'count', measuredAt: Timestamp (real reading time, UTC),
source: 'wear_os'|'health_connect', createdAt: serverTimestamp}`. Immutable after create;
only `patientId == auth.uid` may create. Three shapes (rules enforce exactly one):

| shape | extra fields | id | written |
|---|---|---|---|
| **5-min heart-rate window** | `min`, `max` (0.1 bpm), `sampleCount` (int ≥ 1), `windowStart` (aligned to 5 min since epoch); `value` = mean rounded to whole bpm; `measuredAt` = window END (`windowStart + 5 min`) | `${uid}_heart_rate_${windowStartMillis}` | when the window closed (+2 min grace Wear OS, +20 min Health Connect) |
| **immediate** out-of-range HR sample | `immediate: true` | `${uid}_heart_rate_imm_${measuredAtMillis}` | at once, when a sample is `> heartRateHigh` or `< heartRateLow` (thresholds from `users.vitalThresholds`, defaults 120/45, cached ≤ 1 h on the phone); max one per direction per window, +1 if it becomes critical (≥150 / ≤40) |
| single (sleep per night; legacy per-sample HR from old app versions; legacy steps) | — | `${uid}_${type}_${measuredAtMillis}` | sleep: once per night (when its total changes) |

Steps are no longer written to `vitals` (they were one doc per change, up to ~96/day): daily totals go to
`vitals_daily.steps` and `users.latestVitals.steps`.
Pure aggregation code: `lib/services/vitals_aggregation.dart` (Dart, unit-tested) mirrored by
`android/app/.../WearVitalsUploader.kt`. Partial Wear OS windows are persisted in SharedPreferences
(`commit()` before the watch DataItem is deleted) and flushed on the next watch batch, on app resume and
on `flushPendingWatchReadings`. A sample that arrives after its window doc was written is not added to that
(immutable) doc; if out of range it still produces an immediate doc.

Server trigger `vitalCreated` (functions/src/core/triggers.js): validates, updates
`users.latestVitals` if newer, and for out-of-range values (30-min cooldown per patient + type + direction)
creates a `crisis_events` doc. **Alerting policy for windows:** windows are NOT evaluated
(`logic/vitals.js skipVitalTrigger(data)`); every breaching sample already produced an immediate doc, so
evaluating the window (whose `max`/`min` breach) would only duplicate the alert. `windowBreach()` exists for
reporting only. Until the trigger calls `skipVitalTrigger` (coordinator follow-up) a window is processed
like a single reading of its mean: correct, but 3 extra reads + 1 write per window, and the 30-min cooldown
prevents duplicates.

### `vitals_daily/{patientId}_{yyyy-MM-dd}` — one summary per patient per LOCAL day
`{patientId, therapistId, date: 'yyyy-MM-dd', hrRestingEstimate, hrAvg, hrMin, hrMax, hrWindows,
sleepHours, steps, updatedAt: serverTimestamp}` — all summary fields optional / nullable; rules allow
exactly these keys, numeric ranges (HR 20-250, hrWindows 0-400, sleep 0-24 h, steps 0-200000), id ==
`${patientId}_${date}`, `date` immutable, no deletes. Created / merged (`set(merge: true)`) by the owner
patient only; read by the patient and their current therapist (query `patientId ==` + `orderBy date desc`,
index `vitals_daily (patientId ASC, date DESC)`).
* `hr*` (Android: written by WearVitalsUploader from Wear OS windows **and** Health Connect windows that
  Dart hands over via the `recordHeartRateWindows` channel, deduplicated by window start; iOS: by Dart).
  `hrRestingEstimate` = nearest-rank 10th percentile of the day's 5-min means, null with < 12 windows (1 h).
  Today: at most every 3 h; a past day once more when it still has unsent windows.
* `sleepHours` (night ending that morning), `steps` (day total): Dart Health Connect path, when the value
  changed; today at most every 3 h unless sleep changed.

### Free-tier budget (Firestore Spark: 20k writes + 50k reads per day for the WHOLE project)
Per patient per day, watch worn 24 h (~1 sample/min = 1,440 samples). "Rules read" = the `get(users/uid)`
in `isOwnPatientStamp`; the backend functions runner reads each new doc once through its listener.

| | before | after (trigger wired to skip windows) | after (trigger not yet changed) |
|---|---|---|---|
| `vitals` creates | 1,440 HR + ≤96 steps + 1 sleep | 288 windows + immediates (0 when in range; ≤12/h per direction while out of range) + 1 sleep | same |
| `users.latestVitals` writes (client) | 1,440 (Kotlin, every sample) + Dart every sync | ≤96 (Kotlin, 15-min throttle) + Dart ≤ 1 per 15 min while open | same |
| `users.latestVitals` writes (trigger) | ~1,440 | ~0 (immediates only) | ~288 |
| `vitals_daily` writes | — | ~9 (hr) + ~3-8 (sleep/steps) | same |
| **writes / patient / day** | **≈ 3,000-4,400** | **≈ 400** | **≈ 690** |
| rules reads | ≈ 1,540 | ≈ 300 | ≈ 300 |
| runner listener reads | ≈ 1,540 | ≈ 290 | ≈ 290 |
| trigger transaction reads (3 per doc) | ≈ 4,600 | ≈ 3 (sleep) + 3 per immediate | ≈ 870 |
| profile reads (Kotlin users doc) | 4 (6-h cache) | 24 (1-h cache, picks up threshold changes) | 24 |
| **reads / patient / day (no therapist screens open)** | **≈ 7,700** | **≈ 620** | **≈ 1,480** |
| therapist vitals panel, per open | ≈ 1,440 (+ ≈ 1,440 every hour left open) | ≤ 320 (+ ≤ 320 every 6 h left open) | same |
| therapist screens listening to `users/{pid}` | 1 read per latestVitals write per open listener (≈ 2,900/day/listener) | ≈ 100/day/listener | ≈ 390 |
| Digital Twin drift card, per open | — | ≤ ~130 (one-shot `get`, no listener) | same |

Capacity (writes are the binding limit, before check-ins / chat / alerts): before ≈ 4-6 patients with a
watch; after ≈ 45-50 (trigger wired) or ≈ 28 (not yet). Further levers if needed: 10-min windows (halves the
288), raising the latestVitals throttle, or moving the trigger evaluation of windows entirely client-side.

### `daily_logs/{id}`, `clinical_assessments/{id}`
Existing shapes. MUST include `patientId == auth.uid`, `therapistId` (from the
patient's `users` doc, never empty / never a name), `timestamp: Timestamp`.
Function `onDailyLogCreated`/`onAssessmentCreated` raises a crisis event when
riskScore ≥ 75, PHQ-9 total ≥ 20, or PHQ-9 item 9 > 0, or for a C-SSRS
screener (below) with risk `high` / `moderate`.

#### `clinical_assessments` type `cssrs` — C-SSRS Screener (Screen Version – Recent)
Written by lib/screens/patient/cssrs_screener_screen.dart. **Exactly** these fields
(rules reject any other key):
`{patientId, therapistId (users doc; null if unlinked), type: 'cssrs',
cssrsAnswers: {q1, q2, q3, q4, q5, q6, q6Recent}, cssrsRisk: 'none'|'low'|'moderate'|'high',
timestamp: serverTimestamp, clientCreatedAt: Timestamp}`.
`q1`, `q2`, `q6` are bool. Skip logic (enforced by rules): `q3`–`q5` are bool when
`q2 == true`, else `null`; `q6Recent` is bool when `q6 == true`, else `null`.
Rules also require `cssrsRisk` to equal the Columbia triage of the answers:

| answers | cssrsRisk | crisis event |
|---|---|---|
| all no | `none` | — |
| Q1 or Q2 yes only | `low` | — (resources offered to patient; shown on therapist card) |
| Q3 yes, or Q6 yes with `q6Recent == false` | `moderate` | `cssrs_moderate`, severity `medium` (function) |
| Q4 or Q5 yes, or Q6 yes with `q6Recent == true` | `high` | `cssrs_high`, severity `critical` (patient app first, function merges) |

Immutable after create. Triage code: `lib/services/clinical_scoring.dart`,
`functions/src/logic/cssrs.js` (identical tables, both unit-tested).

### `crisis_events/{id}` — every therapist-facing alert (one stream)
`{patientId, therapistId, patientName, eventType:
'checkin_crisis'|'sos'|'chat_crisis'|'high_risk'|'phq9_severe'|'cssrs_high'|'cssrs_moderate'|'vital_high'|'vital_low',
severity: 'critical'|'high'|'medium', title, message,
vital?: {type, value, unit, threshold}, acknowledged: false,
acknowledgedAt?: Timestamp, timestamp: Timestamp (server)}`.
Patients create only for themselves (`sos`, `checkin_crisis`, `chat_crisis`;
`phq9_severe` (critical|high) and `cssrs_high` (critical only) ONLY at the
deterministic id `assessment_<assessmentId>`, written before the assessment so
the alert is queued even offline; `onAssessmentCreated` merges server-verified
facts into the same doc and never touches `acknowledged*`);
functions create the rest (`cssrs_moderate` is function-only).
An unacknowledged `cssrs_high` keeps the patient's Clinical status at CRITICAL
on the therapist card until acknowledged. Therapist of that patient may update ONLY
`acknowledged`, `acknowledgedAt`, `acknowledgedBy`.
Function `onCrisisEventCreated` sends a high-priority push to the therapist
(Android channel `clinical_critical`, data `{type:'crisis', eventId, patientId}`).

Watch SOS: the Wear OS app sends DataItem `/mindtwin/sos/<pressedAtMillis>`
`{pressedAt: Long, source: 'wear_os'}`; the phone (WearSosHandler.kt) writes
`crisis_events/wear_sos_<uid>_<pressedAt>` `{eventType:'sos', severity:'critical',
source:'wear_os', title:'SOS alert (watch)', clientCreatedAt, ...}` (patient create rule)
and posts a local notification that opens Safety Resources.

### `safety_plans/{patientId}` — Stanley-Brown Safety Plan (Stanley & Brown 2012)
`{patientId, therapistId (users doc; null if unlinked), warningSigns: string[],
copingStrategies: string[], distractionsPeople: [{name, phone?}],
helpContacts: [{name, phone?}], professionals: [{name, phone?}],
environmentSafety: string, reasonsToLive: string[],
updatedAt: serverTimestamp, updatedBy: uid}`. Lists ≤ 20 items; strings ≤ 500
(environmentSafety ≤ 2000). Patient reads/writes own (full doc); the patient's
current therapist reads and creates/merges ONLY the content fields + `therapistId`
(= self), `updatedAt`, `updatedBy`. No delete. The first `helpContacts` entry with
a phone is the SOS "Text my trusted contact" target (SMS app, never sent silently).

### `chats/{chatId}` and `chats/{chatId}/messages/{messageId}`
`chatId = sorted([uidA, uidB]).join('__')`. Chat doc:
`{participants: [uidA, uidB], names: {uid: name}, lastMessage, lastSenderId,
lastMessageAt: Timestamp, unread: {uid: int}}`. Message:
`{id, senderId, receiverId, senderName, text, createdAt: serverTimestamp,
read: false}`; the SAME `messageId` is used for any local/backend copy.
Only participants read/write; a patient may only chat with their own therapist.
Function `onMessageCreated` pushes to `receiverId` (channel `chat_messages`,
data `{type:'chat', chatId, senderId}`).

### `appointments/{id}`
`{patientId, therapistId, patientName, therapistName,
requestedBy: 'patient'|'therapist',
status: 'requested'|'scheduled'|'declined'|'cancelled'|'completed'|'no_show',
scheduledAt: Timestamp|null, proposedAt: Timestamp|null, durationMinutes: 30|45|60,
isVirtual: bool, meetingUrl: string|null, reason, notes,
createdAt, updatedAt: serverTimestamp, cancelledBy?}`.
Lifecycle: patient creates `requested` (with `proposedAt`); therapist sets
`scheduled` (+`scheduledAt`) or `declined`; therapist may also create directly
as `scheduled`; either party may `cancelled`; therapist sets `completed`/`no_show`.
Function `onAppointmentWritten` sets `meetingUrl`
(`https://meet.jit.si/MindTwin-<id>-<random>`) when it becomes `scheduled` &
`isVirtual`, and pushes the other party (channel `appointments`, data
`{type:'appointment', appointmentId}`).

## Digital Twin drift index (early-warning, personal baseline — not diagnostic)
`lib/services/digital_twin_service.dart` (pure, unit-tested) + `lib/widgets/twin_drift_card.dart`.
Inputs (one-shot reads): last 28 days of `vitals_daily` (hrRestingEstimate, sleepHours, steps), `daily_logs`
(wellbeingScore, else 100 − riskScore), `clinical_assessments` (PHQ-9, GAD-7 totals). One value per local day.
* Baseline per signal: median + MAD of the days before the recent window; needs ≥ 7 days (PHQ-9/GAD-7:
  ≥ 2 results, since they are taken every 1-2 weeks) else "learning baseline: N/7 days". Scale =
  max(1.4826·MAD, floor) — floors: resting HR 3 bpm, sleep 0.5 h, steps 1,000, wellbeing 7, PHQ-9 2.5,
  GAD-7 2 (half the minimal important change).
* Recent: median of the last 3 days with ≥ 2 days of data (sleep / check-in include today; resting HR /
  steps use the 3 complete days ending yesterday); PHQ-9 / GAD-7: latest result of the last 7 days.
* Score per signal = robust z in the clinically worse direction only, clamped 0-4: resting HR ↑, sleep ↓
  (or > 2 units ↑, hypersomnia), steps ↓, wellbeing ↓, PHQ-9 ↑, GAD-7 ↑.
* Index 0-100 = 100·Σ w·score/4 / Σ w over scored signals; weights resting HR 1.0, sleep 1.0, steps 0.75,
  check-in 1.0, PHQ-9 1.5, GAD-7 1.0. Level: < 25 stable, < 50 watch, ≥ 50 drifting; ≥ watch if any signal
  scores ≥ 3; ≤ watch with fewer than 2 scored signals; no scored signal → learning.
* Therapist (patient details, under Clinical status): index, level, explanations, labelled "Early-warning,
  personal-baseline signal — not diagnostic"; listed in the Clinical status card's early warnings, never in
  the level (`ClinicalScoring` stays instrument-based). Patient (My Twin): "Your recent pattern vs your
  usual", stable / "some changes" only, 28-day sparklines, no index.
* Optional notification (not wired): `functions/src/logic/drift.js` `shouldNotifyDrift` (transition into
  drifting, 3-day cooldown, low priority, never a crisis event). Wiring needs a persisted snapshot such as
  owner-writable `users/{uid}.latestDrift {level, index, at}` (rules change) and a users-update trigger.

## Push notification channels (Android)
`clinical_critical` (max importance), `chat_messages` (high), `appointments` (default).
Data payload `type` ∈ `crisis | chat | appointment`.

## Separate apps
| app | applicationId | APP_MODE |
|---|---|---|
| Patient (+ Wear OS companion) | `com.mindtwin.patient` (wear app uses the same id) | `patient` |
| Therapist | `com.mindtwin.therapist` | `therapist` |
Built via Gradle product flavors `patient` / `therapist`.
