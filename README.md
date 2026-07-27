# MindTwin

MindTwin is a Flutter mental health app with Firebase-backed authentication and Firestore user storage, plus a Node.js backend for local API workflows.

## What Is In This Repo

- Flutter app under `lib/`
- Firebase auth and Firestore integration
- Node backend under `backend/`
- Firestore rules in `firestore.rules`
- Deployment config in `firebase.json` and `render.yaml`

## Current Runtime Flow

- Patient signup and login use Firebase Auth.
- Therapist selection loads from Firestore `users` documents where `role == therapist`.
- The app falls back to a local therapist list only when Firestore is unavailable.
- The backend runs separately on port `5000` and serves the API routes in `backend/index.js`.

## Important Files

- App entry: `lib/main.dart`
- Firebase config: `lib/firebase_options.dart`
- Auth and signup flow: `lib/screens/auth/patient_auth_screen.dart`
- Shared auth logic: `lib/services/auth_service.dart`
- Backend entry point: `backend/index.js`
- Backend package config: `backend/package.json`
- Firestore rules: `firestore.rules`

## Run Locally

### 1. Get Flutter dependencies

```powershell
flutter pub get
```

### 2. Start the backend

```powershell
cd backend
npm install
npm start
```

### 3. Run the Flutter app on Chrome

```powershell
cd ..
flutter run -d chrome
```

If you need a clean restart:

```powershell
flutter clean
flutter pub get
flutter run -d chrome
```

## Firebase Setup

The project is configured for Firebase project `mindtwin-60879`.

### Deploy Firestore rules

```powershell
firebase deploy --only firestore:rules --project mindtwin-60879
```

### Export Firebase Auth users for verification

```powershell
firebase auth:export auth_users.json --project mindtwin-60879
```

### Notes

- The therapist selector reads from Firestore and should show the available therapist accounts stored in Firebase.
- The project runs best on Flutter web in this workspace because the Windows desktop toolchain is not configured.
- The backend also has a dedicated guide in `backend/README.md`.

## Repo Hygiene

This cleanup removes duplicate setup/status documents so the root README stays current and the folder stays easier to navigate.
