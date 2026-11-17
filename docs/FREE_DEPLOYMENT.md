# MindTwin on a zero budget (Firebase Spark + laptop / Render free)

Cloud Functions need the paid Blaze plan. This guide runs MindTwin on the
**free Spark plan** instead. Everything that `functions/` does is done by the
Node backend (`backend/`):

| Cloud Functions (Blaze) | Free replacement in `backend/` |
|---|---|
| 5 callables (`registerPatient`, `registerTherapist`, `joinTherapist`, `approveTherapist`, `getMyInviteCode`) | `POST /api/callable/:name` (`src/firebase/callableRouter.js`) — verifies the Firebase ID token (`verifyIdToken(token, checkRevoked=true)`), per-user rate limit |
| Firestore triggers (vitals, daily logs, assessments, crisis events, chat messages, appointments) | Firestore realtime listeners (`src/firebase/triggerRunner.js`, `listenerSpecs.js`) |
| `onAuthUserDeleted` | Orphan sweep every 24 h + `POST /api/runner/cleanup-orphans` (admin) |

Both run **the same code**: `functions/src/core/*` + `functions/src/logic/*`
(no npm dependencies; the backend injects its own `firebase-admin`). The
backend loads it with a relative `require` from `backend/src/firebase/coreLoader.js`,
so the backend must always be deployed **from a full repo checkout**
(`functions/src` next to `backend/`). `functions/` stays deployable to Blaze
unchanged if money appears later — then set `FUNCTIONS_RUNNER_ENABLED=false`
on the backend so the triggers do not run twice (running twice is still safe,
see "Duplicates", but wastes quota).

What is free on Spark: Authentication (email/password), Cloud Firestore
(within the daily quota), Cloud Messaging (FCM), Hosting, and setting custom
claims with the Admin SDK. Do **not** enable anything that asks you to upgrade.

---

## 1. Firebase project (Spark)

1. <https://console.firebase.google.com> → your project (`mindtwin-60879`) →
   ⚙ *Usage and billing* → confirm the plan is **Spark** (no card on file).
2. *Build → Authentication → Sign-in method*: enable **Email/Password**.
3. *Build → Firestore Database*: create the database (production mode).
4. **Service account** for the backend and admin scripts:
   ⚙ *Project settings → Service accounts → Generate new private key*.
   Save it as `backend/config/firebase-service-account.json`
   (git-ignored — never commit, e-mail or paste it in chat).

## 2. Release keystore (once; keep it forever)

Android apps must be signed with the **same** key for every update, and the
SHA-1 of that key is registered in Firebase.

```powershell
keytool -genkeypair -v -keystore C:\mindtwin-keys\mindtwin-release.jks `
  -alias mindtwin -keyalg RSA -keysize 2048 -validity 10000
```

(`keytool` ships with Android Studio:
`"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"`.)
Back up the `.jks` and its passwords in two safe places — losing it means
nobody can install updates over the old app.

Create `android/key.properties` (git-ignored):

```properties
storeFile=C:/mindtwin-keys/mindtwin-release.jks
storePassword=<store password>
keyAlias=mindtwin
keyPassword=<key password>
```

Print the SHA-1 / SHA-256:

```powershell
keytool -list -v -keystore C:\mindtwin-keys\mindtwin-release.jks -alias mindtwin
```

## 3. Register the Android apps

⚙ *Project settings → Your apps → Add app → Android*, twice:

| package name | nickname |
|---|---|
| `com.mindtwin.patient` (also used by the Wear OS app) | MindTwin Patient |
| `com.mindtwin.therapist` | MindTwin Therapist |

For **each** app add the release **SHA-1** (and SHA-256) from step 2
(*Add fingerprint*). Then download `google-services.json` (it contains both
apps once both are registered) to `android/app/google-services.json`
(git-ignored). If you also build debug APKs, add the debug key's SHA-1
(`keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android`).

## 4. Claims backfill, then rules + indexes (free)

The rules lock out every account that has no `role` claim, so give existing
accounts their claim **before** deploying the rules.

```powershell
cd functions; npm ci; cd ..        # the admin scripts load firebase-admin from functions/
$env:GOOGLE_APPLICATION_CREDENTIALS="backend\config\firebase-service-account.json"
node scripts/backfill-claims.js           # dry run: read the report
node scripts/backfill-claims.js --apply   # write the claims
npm i -g firebase-tools; firebase login
firebase use mindtwin-60879
firebase deploy --only firestore:rules,firestore:indexes
```

Deploy **only** `firestore:rules,firestore:indexes` — never `firebase deploy`
without `--only` (it would try to deploy functions and ask for Blaze).
Index builds take a few minutes. The index file includes a
collection-group index on `messages.createdAt`; until it is built the backend
logs `listener chat_messages failed ... (missing index?)` and retries with
backoff — chat pushes start working once the build finishes.

## 5. Admin and therapist approval

```powershell
node scripts/make-admin.js admin@clinic.example      # optional: admin claim
node scripts/approve-therapist.js dr.smith@clinic.example
```

A therapist first signs up in the therapist app (status *pending*); then run
`approve-therapist.js` with their e-mail. It prints the therapist's **invite
code**; patients register with that code. The therapist signs out and in
again (or reopens the app) to pick up the new role.

## 6. Run the backend on the clinic laptop (recommended for the demo)

Requirements: Node 22 (or ≥ 20), the service-account file from step 1, a
**correct clock** (Windows: *Settings → Time → Sync now*; ID tokens are
rejected when the server clock is far off).

```powershell
cd backend
npm ci                      # includes pm2 (dev dependency)
```

Add to `backend/.env` (create it if missing; never commit it):

```dotenv
GOOGLE_APPLICATION_CREDENTIALS=config/firebase-service-account.json
PORT=5000
RUNNER_INSTANCE_ID=laptop
# FUNCTIONS_RUNNER_ENABLED=false   # only if Cloud Functions are deployed
```

Start it under pm2 so it restarts on crashes:

```powershell
npm run start:pm2           # npx pm2 start index.js --name mindtwin-backend --time
npm run logs:pm2            # look for: "trigger runner started; active listeners: vitals, daily_logs, ..."
npm run save:pm2
```

Check `http://localhost:5000/health`: `runner.enabled` is `true` and every
listener has `subscribed: true`. To start pm2 on boot on Windows use
`backend/install_autostart_windows.ps1`.

Keep the laptop awake and plugged in (*Power settings → Never sleep*). While
the backend is down nothing is lost: patients' data still reaches Firestore
and therapists still see crisis events live in the app, but **vital-sign
alerts are not created and no push notifications are sent** until the backend
runs again. On restart it catches up on everything written in the last 24 h
(`RUNNER_MAX_CATCHUP_MS`) — alerts arrive late, never twice.

### How the phones find the laptop

The phones and the laptop must be on the **same network**:

* **Laptop hotspot (most reliable in a hospital):** Windows *Settings →
  Network → Mobile hotspot* → on; connect the phones to it. Hospital guest
  Wi-Fi often blocks phone-to-phone/laptop traffic ("client isolation").
* The apps find the backend automatically by UDP broadcast
  (`LanDiscoveryService`, port 47777) and remember it; fall-backs are a URL
  saved in the app settings and the build-time `MINDTWIN_API_BASE_URL`.
* Windows Firewall: when Node first starts, allow it on **Private** networks
  (TCP 5000 and UDP 47777). Mark the hotspot / Wi-Fi as a *Private* network.

If the backend cannot be reached, sign-up / invite-code screens show
*"MindTwin server is not reachable — make sure the clinic server is running."*
Accounts created while the server was unreachable are kept; signing in again
finishes the registration.

## 7. Optional: Render free tier

`render.yaml` defines a **free** Node web service built from the repo root
(`cd backend && npm ci --omit=dev`, start `cd backend && node index.js`).
In the Render dashboard (*New → Blueprint* from your GitHub repo) set:

| env var | value |
|---|---|
| `GOOGLE_APPLICATION_CREDENTIALS_JSON` | the whole service-account JSON (or base64 of it) |
| `LAN_DISCOVERY_ENABLED` | `false` (already in render.yaml) |
| `RUNNER_INSTANCE_ID` | `render` (already in render.yaml) |
| `JWT_SECRET`, `GEMINI_API_KEY`, ... | as for the laptop |

Free-tier facts (check render.com/pricing, they change):

* The service **sleeps after ~15 minutes without inbound HTTP traffic** and
  takes up to about a minute to wake. **While asleep the trigger runner is
  stopped: no vital alerts, no pushes.** Firestore listeners are outbound
  connections and do not keep it awake. If you rely on Render, point a free
  uptime monitor (e.g. UptimeRobot, every 5–10 min) at
  `https://<service>.onrender.com/health`. Free instance hours are about
  750/month per workspace — enough for **one** always-on service, so do not
  keep the ML service awake too.
* No persistent disk: the local SQLite file is wiped on every restart. All
  clinical data lives in Firestore; the runner keeps its progress in the
  Firestore doc `_runner/render`.
* The apps call Render through `MINDTWIN_API_BASE_URL` (step 8). A sleeping
  instance fails the quick health probe, so the app then calls the build-time
  URL directly with a 75 s timeout and Render wakes up on that request.

Laptop **and** Render may run at the same time (e.g. Render as a fallback):
each instance keeps its own `_runner/{RUNNER_INSTANCE_ID}` state, and pushes
are never sent twice (see "Duplicates").

## 8. Build the APKs

```powershell
flutter pub get
# Laptop / LAN only (discovery finds the server):
flutter build apk --release --flavor patient   --dart-define=APP_MODE=patient
flutter build apk --release --flavor therapist --dart-define=APP_MODE=therapist
# With Render as server, add:  --dart-define=MINDTWIN_API_BASE_URL=https://<service>.onrender.com
```

Output: `build\app\outputs\flutter-apk\app-patient-release.apk` and
`app-therapist-release.apk`. Wear OS app (same package as the patient app,
same signing key):

```powershell
cd android; .\gradlew.bat :wear:assembleRelease; cd ..
# -> android\wear\build\outputs\apk\release\wear-release.apk
```

## 9. Install (sideload)

Enable *Developer options → USB debugging* on each phone, then:

```powershell
adb devices
adb install -r build\app\outputs\flutter-apk\app-patient-release.apk     # patient phones
adb install -r build\app\outputs\flutter-apk\app-therapist-release.apk   # therapist phones
```

Watch: enable *Developer options → ADB debugging* and *Wireless debugging*
on the watch, then

```powershell
adb pair <watch-ip>:<pair-port>          # code shown on the watch
adb connect <watch-ip>:<port>
adb -s <watch-ip>:<port> install -r android\wear\build\outputs\apk\release\wear-release.apk
```

On first launch allow notifications (Android 13+) so crisis pushes appear.

## 10. Free-tier limits to keep in mind

Spark Firestore quota (per day, resets at midnight US Pacific time):
**50,000 document reads, 20,000 writes, 20,000 deletes**, 1 GiB stored,
10 GiB/month egress. When a quota is exhausted, Firestore **refuses requests
until the reset** — the apps stop syncing and alerts stop. Watch
*Firestore → Usage* during the demo.

Rough per-event cost of the runner: a vital reading ≈ 4 reads + 1–3 writes;
a crisis push ≈ 3 reads + 2 writes; the runner's progress doc is written at
most every 30 s while events arrive. Every backend (re)start re-reads the
docs of the last ~15–20 minutes (and daily logs of the last ~2 h). A small
demo (a few patients, a watch sending a heart-rate reading every few minutes)
fits comfortably; dozens of patients with per-minute vitals will not.

## Duplicates and restarts (how correctness is kept)

* Listeners deliver all matching docs on (re)subscribe. Each listener only
  handles changes whose **server** time (`createTime`/`updateTime`) is newer
  than its persisted watermark minus a 2-minute overlap, and remembers which
  changes inside that overlap it already handled.
* All handlers are idempotent: crisis docs use deterministic ids
  (`vital_<id>`, `assessment_<id>`, `dailylog_<id>`) and every push claims
  `push_receipts/<key>` in a transaction first, so two backends (or a backend
  plus Cloud Functions) never send the same push twice. Appointments keep a
  server-only `_runner_appointments/<id>` doc with the last handled version.
* A failing handler is retried with exponential backoff (max 5 min) and the
  watermark never moves past it, so it is retried after a restart too.
* `GET /health` → `runner.listeners[]` shows `subscribed`, `watermark`,
  `pendingRetries`, `errors`, `lastError`; `runner.lastEventAt` is the last
  handled event.

## Auth account deletion

There is no free trigger for deleted Auth accounts. The backend sweeps every
24 h (`RUNNER_ORPHAN_SWEEP_HOURS`, `0` = off): profiles (`users/{uid}`) and
push tokens of uids that no longer exist in Auth are removed (each one is
re-checked with `getUser` first; clinical records are retained). The sweep
refuses to run if Auth lists no users or if more than half of the profiles
look orphaned (wrong project). An admin can trigger it with
`POST /api/runner/cleanup-orphans` (Bearer ID token with the `admin` claim,
body `{"dryRun": true}` to preview).

## Tests

```powershell
cd functions; npm test; npm run lint
cd ..\backend; npx jest
$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
npm run test:emulator        # Auth+Firestore emulators: callables over HTTP, runner, restarts, push dedupe
cd ..\test\rules; npm run test:emulator
```
