# MindTwin

MindTwin is an AI-assisted mental health platform with two experiences:
- Patient app flow for daily assessment, notes, chat, and personal digital twin insights.
- Therapist command center for risk monitoring, crisis triage, and intervention planning.

This README is a live summary of the repository structure and runtime surfaces.

## 1. Product Scope

MindTwin combines:
- Clinical-style daily check-ins (mood/sleep/anxiety/energy + wearable context)
- Local ML-style fallbacks in Flutter plus clinical/chat services in Node for risk, crisis, and intervention workflows
- AI assistant flows (patient companion and therapist assistant)
- Firestore-based real-time monitoring for therapist workflows

## 2. High-Level Architecture

### Frontend
- Flutter app in [lib](lib)
- Patient and therapist UI flows under [lib/screens](lib/screens)
- Service layer in [lib/services](lib/services)
- Core config/theme in [lib/core](lib/core)

### Backend (Node API)
- Express server in [backend](backend)
- Primary startup file: [backend/index.js](backend/index.js)
- Clinical routes: [backend/src/routes/clinical.js](backend/src/routes/clinical.js)
- Chat/crisis routes: [backend/src/routes/chat.js](backend/src/routes/chat.js)
- Compatibility shims for legacy UI calls: [backend/src/routes/ml.js](backend/src/routes/ml.js) and [backend/src/routes/gemini.js](backend/src/routes/gemini.js)

### Data Layer
- Firebase Firestore collections for logs, alerts, interventions, users, and chat records.
- Local DB service exists in Flutter for non-web paths; web primarily relies on Firestore/API fallback patterns.

## 3. Repository Layout (Important Paths)

- Frontend app entry: [lib/main.dart](lib/main.dart)
- Patient screens: [lib/screens/patient](lib/screens/patient)
- Therapist screens: [lib/screens/therapist](lib/screens/therapist)
- Flutter ML service clients: [lib/services](lib/services)
- Node backend: [backend](backend)
- No Python/FastAPI ML service is present in this repository.

## 4. Implemented ML Features (Backend + Frontend)

### ML 1: Sentiment Analysis
Frontend:
- Client: [lib/services/ml_sentiment_service.dart](lib/services/ml_sentiment_service.dart)
- Used in patient check-in notes flow: [lib/screens/patient/daily_checkin_screen.dart](lib/screens/patient/daily_checkin_screen.dart)
- Used in patient chat crisis detection: [lib/screens/patient/patient_ai_chat_screen.dart](lib/screens/patient/patient_ai_chat_screen.dart)

### ML 2: Risk Prediction (7-day)
Frontend:
- Client: [lib/services/ml_risk_service.dart](lib/services/ml_risk_service.dart)
- Patient digital twin forecast UI: [lib/screens/patient/my_twin_screen.dart](lib/screens/patient/my_twin_screen.dart)
- Therapist dashboard risk cards: [lib/screens/therapist/dashboard_tab.dart](lib/screens/therapist/dashboard_tab.dart)

### ML 3: Anomaly Detection
Frontend:
- Client: [lib/services/ml_anomaly_service.dart](lib/services/ml_anomaly_service.dart)
- Triggered after patient check-in submit: [lib/screens/patient/daily_checkin_screen.dart](lib/screens/patient/daily_checkin_screen.dart)
- Therapist alert center displays anomalies: [lib/screens/therapist/real_time_alerts_center_screen.dart](lib/screens/therapist/real_time_alerts_center_screen.dart)

### ML 4: Personalized Intervention Recommender
Frontend:
- Local recommendation logic: [lib/services/advanced_clinical_ai_service.dart](lib/services/advanced_clinical_ai_service.dart)
- Therapist simulator recommendation panel: [lib/screens/therapist/simulator_tab.dart](lib/screens/therapist/simulator_tab.dart)

### ML 5: NLP Crisis Detection
Frontend:
- Called from patient chat message flow: [lib/screens/patient/patient_ai_chat_screen.dart](lib/screens/patient/patient_ai_chat_screen.dart)
- Crisis events written to Firestore and surfaced in therapist alert center: [lib/screens/therapist/real_time_alerts_center_screen.dart](lib/screens/therapist/real_time_alerts_center_screen.dart)

## 5. AI Assistant Integration (Gemini)

- Shared Gemini service: [lib/services/gemini_service.dart](lib/services/gemini_service.dart)
- Config constants: [lib/core/config/app_config.dart](lib/core/config/app_config.dart)
- Patient assistant UI: [lib/screens/patient/patient_ai_chat_screen.dart](lib/screens/patient/patient_ai_chat_screen.dart)
- Therapist assistant UI: [lib/screens/therapist/therapist_ai_chat_screen.dart](lib/screens/therapist/therapist_ai_chat_screen.dart)
- Advanced clinical explanation helper: [lib/services/advanced_clinical_ai_service.dart](lib/services/advanced_clinical_ai_service.dart)

## 6. Core Frontend Screens

### Patient
- Daily assessment and note capture: [lib/screens/patient/daily_checkin_screen.dart](lib/screens/patient/daily_checkin_screen.dart)
- Digital twin risk/trend view: [lib/screens/patient/my_twin_screen.dart](lib/screens/patient/my_twin_screen.dart)
- AI chat with background crisis detection: [lib/screens/patient/patient_ai_chat_screen.dart](lib/screens/patient/patient_ai_chat_screen.dart)
- Safety resources: [lib/screens/patient/safety_resources_screen.dart](lib/screens/patient/safety_resources_screen.dart)

### Therapist
- Dashboard metrics and risk forecasts: [lib/screens/therapist/dashboard_tab.dart](lib/screens/therapist/dashboard_tab.dart)
- Patient list + sentiment badges: [lib/screens/therapist/patients_tab.dart](lib/screens/therapist/patients_tab.dart)
- Intervention simulator + recommendations: [lib/screens/therapist/simulator_tab.dart](lib/screens/therapist/simulator_tab.dart)
- Real-time crisis/anomaly alert center: [lib/screens/therapist/real_time_alerts_center_screen.dart](lib/screens/therapist/real_time_alerts_center_screen.dart)

## 7. Backend API Surface

### Node Base
- Default local URL: http://localhost:5000

### Compatibility Routes (Node)
Defined in [backend/src/routes/ml.js](backend/src/routes/ml.js):
- POST /api/ml/sentiment
- POST /api/ml/predict-risk
- POST /api/ml/detect-anomaly
- POST /api/ml/recommend-intervention
- POST /api/ml/detect-crisis

Defined in [backend/src/routes/gemini.js](backend/src/routes/gemini.js):
- POST /api/gemini/chat

## 8. Firestore Collections in Use

Primary collections observed in project flows:
- users
- daily_logs
- anomalies
- crisis_events
- interventions
- messages

## 9. Environment and Dependencies

### Flutter
- Managed by [pubspec.yaml](pubspec.yaml)

### Node
- Managed by [backend/package.json](backend/package.json)

### Legacy ML Compatibility
- Legacy ML-style behavior is now implemented through Flutter fallbacks and Node compatibility routes.

## 10. Run Instructions (Local)

### 10.1 Start Node backend

```powershell
Set-Location C:\MIndTwin\backend
node index.js
```

### 10.2 Start Flutter frontend

```powershell
Set-Location C:\MIndTwin
flutter pub get
flutter run -d chrome
```

If you hit stale terminal jobs on Windows, clean up and relaunch:

```powershell
Get-Process -Name dart,flutter,chrome -ErrorAction SilentlyContinue | Stop-Process -Force
Set-Location C:\MIndTwin
flutter clean
flutter pub get
flutter run -d chrome
```

## 11. Verification Checklist (Demo/Review)

### Patient flow
1. Open Check-In and submit assessment with clinical notes.
2. Confirm note sentiment fields are saved and reflected in therapist view.
3. Open My Twin and check 7-day risk forecast/trend.
4. Send distress text in patient chat and verify crisis event handling.

### Therapist flow
1. Open dashboard and validate patient risk forecast cards.
2. Open patients tab and validate sentiment badge display.
3. Open simulator and validate intervention recommendations appear.
4. Open real-time alerts and validate crisis/anomaly triage actions.

## 12. Known Runtime Notes

- Web builds do not support all local DB operations used by mobile paths; Firestore/API-backed flows are relied on for web demos.
- If Flutter terminal shows batch termination prompts, answer and relaunch from project root.
- Fonts warning (Noto missing glyph sets) can appear in web debug; not a blocker for core ML flows.

## 13. Reviewer Prompt (Copy/Paste)

Use this prompt in another AI:

```text
Review this MindTwin project end-to-end.
Focus on:
1) ML pipeline correctness across Node proxy and Python microservice endpoints.
2) Frontend-backend contract consistency for sentiment/risk/anomaly/intervention/crisis payloads.
3) Therapist safety workflow robustness (critical alert acknowledgement and dismissal rules).
4) Web-vs-mobile behavior differences and failure fallbacks.
5) Security/privacy concerns around PHI, API keys, and Firestore writes.
6) Missing tests and highest-risk production bugs.

Please provide findings ordered by severity with concrete file references and suggested fixes.
```

## 14. Current State Summary

The repository includes a complete multi-model ML backend and connected Flutter frontend workflows for patient and therapist experiences, with Node proxy fallbacks and real-time Firestore monitoring.
