# 🚀 MindTwin Quick Start Guide

## 📦 Installation (5 minutes)

### Step 1: Install Flutter Dependencies
```bash
cd mindtwin
flutter pub get
```

### Step 2: Firebase Setup (Optional for Demo Mode)

The app works in **demo mode** without Firebase, but for full functionality:

1. **Create Firebase Project**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Click "Add Project"
   - Name it "MindTwin"

2. **Enable Firestore**
   - In Firebase Console, go to "Firestore Database"
   - Click "Create Database"
   - Start in **test mode** (for development)

3. **Add Firebase to Flutter**
   
   **For Android:**
   ```bash
   # Download google-services.json from Firebase Console
   # Place it in: mindtwin/android/app/
   ```
   
   **For iOS:**
   ```bash
   # Download GoogleService-Info.plist from Firebase Console
   # Place it in: mindtwin/ios/Runner/
   ```

4. **Initialize FlutterFire**
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

### Step 3: Run the App
```bash
flutter run
```

---

## 🎮 Using Demo Mode

The app includes a **demo patient** that works without Firebase:

### Patient Portal Demo
1. Select "Patient Portal" on launch
2. **Daily Check-In**: Adjust the 3 sliders (Mood, Sleep, Energy)
3. **Voice Journal**: Tap to simulate recording (visual only)
4. **My Twin**: View 7-day wellbeing chart with mock data
5. **SOS Button**: Test crisis alert (requires Firebase)

### Therapist Dashboard Demo
1. Select "Therapist Dashboard" on launch
2. **Dashboard Tab**: View "James K." - 91% risk patient
3. **Patients Tab**: See list of 3 demo patients
4. **Simulator Tab** (CENTERPIECE):
   - Click on intervention buttons
   - Watch the 30-day trajectory update in real-time
   - See risk reduction calculations
5. **Network Tab**: View animated federated learning visualization

---

## 🎯 Key Features to Test

### 1. Risk Pulse Animation
- Navigate to **Therapist Dashboard** → **Patients Tab**
- See the **red pulsing circle** on high-risk patients (≥75%)

### 2. Intervention Simulator
- Go to **Simulator Tab**
- Click **"Increase Sessions"** button
- Observe the **green trajectory line** showing 50% risk reduction
- Try different interventions and compare

### 3. Digital Twin Chart
- Patient Portal → **My Twin**
- See fl_chart visualization of 7-day wellbeing scores
- Click **"AI got this wrong?"** for feedback dialog

### 4. Glassmorphism UI
- All cards use glassmorphism with gradient overlays
- Dark Medical Mode theme throughout
- Material 3 animated transitions

### 5. Best Contact Window
- Simulator Tab shows **"Best Contact Window"**
- Based on patient activity patterns (mock data)

---

## 📱 Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| **Android** | ✅ Fully Supported | Tested on Android 10+ |
| **iOS** | ✅ Fully Supported | Requires iOS 12+ |
| **Web** | ⚠️ Partial | NavigationRail ideal for desktop |
| **Desktop** | ⚠️ Partial | Windows/macOS/Linux |

---

## 🔧 Troubleshooting

### Issue: "Package not found" errors
```bash
flutter clean
flutter pub get
```

### Issue: Firebase connection errors
- Check `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) placement
- Run `flutterfire configure` again

### Issue: Chart not displaying
- Ensure `fl_chart: ^0.66.0` is in pubspec.yaml
- Run `flutter pub get`

### Issue: Audio recording not working
- Add permissions to AndroidManifest.xml:
  ```xml
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  ```
- Add to Info.plist (iOS):
  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>We need access to record voice journals</string>
  ```

---

## 🎨 Customization

### Change Theme Colors
Edit `lib/core/theme/app_theme.dart`:
```dart
static const Color primaryIndigo = Color(0xFF6366f1); // Change this
```

### Adjust Risk Calculation Weights
Edit `lib/services/firebase_service.dart`:
```dart
// Digital Twin Engine weights
(voiceScore * 0.20) +      // Adjust these percentages
(sentimentScore * 0.20) +
(sleepScore * 0.20) +
(selfReportScore * 0.30) +
(behaviorScore * 0.10)
```

### Modify Intervention Effects
Edit `lib/models/intervention.dart`:
```dart
static Map<InterventionType, double> get riskReductionConstants {
  return {
    InterventionType.callPatient: 0.15,  // Change from 15% to your value
    // ...
  };
}
```

---

## 📚 Next Steps

1. **Add Real Authentication**
   - Implement Firebase Auth
   - Replace hardcoded user IDs

2. **Integrate Voice Analysis**
   - Connect to ML model for tone detection
   - Use Claude API for sentiment analysis

3. **Deploy to Production**
   - Switch Firestore to production rules
   - Set up CI/CD pipeline
   - Configure app signing

4. **Add Push Notifications**
   - Firebase Cloud Messaging
   - Therapist crisis alerts
   - Daily check-in reminders

---

## 💡 Tips

- **Development**: Use hot reload (`r` in terminal) for fast iteration
- **Debugging**: Use Flutter DevTools for performance analysis
- **Testing**: Run `flutter test` for unit tests
- **Production**: Build with `flutter build apk --release` (Android) or `flutter build ios --release` (iOS)

---

## 📞 Need Help?

- **GitHub Issues**: [github.com/yourusername/mindtwin/issues](https://github.com)
- **Flutter Docs**: [docs.flutter.dev](https://docs.flutter.dev)
- **Firebase Docs**: [firebase.google.com/docs](https://firebase.google.com/docs)

---

**Happy Coding! 🚀**
