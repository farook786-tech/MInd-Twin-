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
`latestVitals: { heartRate: {value, measuredAt}, sleepHours: {value, measuredAt}, steps: {value, measuredAt} }`.

Therapist-set thresholds (therapist of that patient may write ONLY this field):
`vitalThresholds: { heartRateHigh: 120, heartRateLow: 45, sleepHoursLow: 4 }` (defaults if absent).

### `therapist_directory/{therapistUid}` — none. Patients link by invite code only.
### `invite_codes/{code}` — server-only (no client access). `{therapistId, active, createdAt}`.

### `fcm_tokens/{token}`
`{uid, platform: 'android'|'ios', app: 'patient'|'therapist', updatedAt}`. Owner
creates/updates/deletes its own docs (`request.resource.data.uid == auth.uid`).
Client registers on login, on `onTokenRefresh`; deletes on logout.

### `vitals/{autoId}` — written by the patient phone (Dart or native Kotlin)
`{patientId, therapistId, type: 'heart_rate'|'sleep'|'steps', value: number,
unit: 'bpm'|'hours'|'count', measuredAt: Timestamp (real reading time, UTC),
source: 'wear_os'|'health_connect', createdAt: serverTimestamp}`.
Doc id SHOULD be deterministic to dedupe: `${patientId}_${type}_${measuredAtMillis}`.
Only `patientId == auth.uid` may create; immutable after.
Function `onVitalCreated` checks thresholds and, if out of range (with a 30-min
cooldown per patient+type), creates a `crisis_events` doc (below) and updates
`users/{patientId}.latestVitals`.

### `daily_logs/{id}`, `clinical_assessments/{id}`
Existing shapes. MUST include `patientId == auth.uid`, `therapistId` (from the
patient's `users` doc, never empty / never a name), `timestamp: Timestamp`.
Function `onDailyLogCreated`/`onAssessmentCreated` raises a crisis event when
riskScore ≥ 75, PHQ-9 total ≥ 20, or PHQ-9 item 9 > 0.

### `crisis_events/{id}` — every therapist-facing alert (one stream)
`{patientId, therapistId, patientName, eventType:
'checkin_crisis'|'sos'|'chat_crisis'|'high_risk'|'phq9_severe'|'vital_high'|'vital_low',
severity: 'critical'|'high'|'medium', title, message,
vital?: {type, value, unit, threshold}, acknowledged: false,
acknowledgedAt?: Timestamp, timestamp: Timestamp (server)}`.
Patients create only for themselves (`sos`, `checkin_crisis`, `chat_crisis`);
functions create the rest. Therapist of that patient may update ONLY
`acknowledged`, `acknowledgedAt`, `acknowledgedBy`.
Function `onCrisisEventCreated` sends a high-priority push to the therapist
(Android channel `clinical_critical`, data `{type:'crisis', eventId, patientId}`).

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

## Push notification channels (Android)
`clinical_critical` (max importance), `chat_messages` (high), `appointments` (default).
Data payload `type` ∈ `crisis | chat | appointment`.

## Separate apps
| app | applicationId | APP_MODE |
|---|---|---|
| Patient (+ Wear OS companion) | `com.mindtwin.patient` (wear app uses the same id) | `patient` |
| Therapist | `com.mindtwin.therapist` | `therapist` |
Built via Gradle product flavors `patient` / `therapist`.
