# Quick Start Guide - MindTwin Implementation

## All-In-One Setup & Testing

### Prerequisites
- Flutter SDK installed
- Node.js 14+ installed (for backend)
- npm installed

---

## 🚀 Part 1: Test Daily Check-In Rapid-Save Fix (5 minutes)

### Build and Run
```bash
cd /mindtwin
flutter clean
flutter pub get
flutter run
```

### Test the Fix
1. Navigate to **Daily Check-In** screen
2. Fill in some data (any values)
3. **Rapidly click "Save Check-in" 5-10 times quickly**
4. ✅ **Result:** Should complete normally without black screen or crash

---

## 🚀 Part 2: Test Data Export Feature (5 minutes)

### Continue from Previous Run or:
```bash
cd /mindtwin
flutter run
```

### Test the Feature
1. Navigate to **Settings/Patient Menu** → **Privacy & Ethics**
2. Click **"Export Your Data"** button
3. See success message with export filename
4. ✅ **Result:** File saved to app documents directory

### Access Exported Data
**Android (from ADB):**
```bash
adb shell
cd /data/data/com.example.mindtwin/app_flutter/
ls -la
cat mindtwin_export_*.json
```

**iOS (requires file app or through code):**
- Data saved to app's Documents folder

---

## 🚀 Part 3: Set Up & Test Backend (15 minutes)

### Step 1: Install Backend
```bash
cd mindtwin-backend
npm install
```

### Step 2: Configure Backend
```bash
cp .env.example .env
# .env is ready with defaults
```

### Step 3: Create Database & Test Data
```bash
npm run migrate
```

**Output should show:**
```
✅ Database connected: ./mindtwin.db
✅ All tables created successfully
✅ Test therapist created: therapist@test.mindtwin.app
✅ Test patient created: patient@test.mindtwin.app
```

### Step 4: Start Backend Server

**Windows:**
```bash
start.bat
```

**Linux/macOS:**
```bash
bash start.sh
```

**Or manually:**
```bash
npm run dev
```

**Expected output:**
```
🚀 MindTwin Backend running on port 5000
📊 Environment: development
🔌 Database: ./mindtwin.db
```

### Step 5: Test Backend (in new terminal)

#### Health Check
```bash
curl http://localhost:5000/health
```

**Expected response:**
```json
{
  "status": "ok",
  "timestamp": "2024-...",
  "environment": "development"
}
```

#### Login Test
```bash
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "therapist@test.mindtwin.app",
    "password": "password123"
  }'
```

**Expected response:**
```json
{
  "success": true,
  "userId": "...",
  "token": "eyJhbGc...",
  "role": "therapist",
  "name": "Dr. Test Therapist"
}
```

#### Copy the Token
From the response above, copy the `token` value. Then test therapist dashboard:

```bash
curl -X GET http://localhost:5000/api/therapists/dashboard \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

**Expected response:** Patient list and dashboard metrics

### Step 6: Connect Flutter App to Backend

#### In new terminal, start Flutter with backend:

**For Android Emulator:**
```bash
cd /mindtwin
flutter run --dart-define=MINDTWIN_API_BASE_URL=http://10.0.2.2:5000
```

**For Physical Device (replace IP):**
```bash
flutter run --dart-define=MINDTWIN_API_BASE_URL=http://192.168.1.100:5000
```

### Step 7: Test Full Integration

1. **In Flutter app:**
   - Register new account OR
   - Login with: `patient@test.mindtwin.app` / `password123`

2. **Create a daily check-in:**
   - Go to Daily Check-In
   - Fill data
   - Click Save
   - ✅ Should sync to backend automatically

3. **Verify in backend:**
   ```bash
   sqlite3 mindtwin.db
   > SELECT * FROM daily_logs;
   > SELECT * FROM users;
   ```

---

## 📊 What's Running

When all three parts are set up:

```
Terminal 1: Flutter App
           ↓
           Uses Backend API at http://10.0.2.2:5000
           ↓
Terminal 2: Node.js Backend Server
           ↓
           Uses SQLite Database (mindtwin.db)
```

---

## 🆘 Troubleshooting

### Issue: "Cannot connect to backend from app"
**Solution:**
- Ensure backend is running: check Terminal 2 for "running on port 5000"
- For emulator, must use `10.0.2.2` (NOT `localhost`)
- For physical device, use actual IP: `adb shell netstat | grep LISTEN`

### Issue: "Database locked" error
**Solution:**
```bash
cd mindtwin-backend
rm mindtwin.db-wal mindtwin.db-shm
```

### Issue: Port 5000 already in use
**Solution:**
```bash
# Edit .env
PORT=5001
npm run dev
# Then run app with: --dart-define=MINDTWIN_API_BASE_URL=http://10.0.2.2:5001
```

### Issue: npm command not found
**Solution:**
- Install Node.js from https://nodejs.org/
- Verify: `node --version` and `npm --version`

### Issue: Flutter app not picking up backend URL
**Solution:**
- Use `--dart-define` flag (not in pubspec.yaml)
- Rebuild: `flutter clean && flutter pub get && flutter run --dart-define=...`

---

## 📝 Test Credentials

### Therapist Account
- Email: `therapist@test.mindtwin.app`
- Password: `password123`

### Patient Account  
- Email: `patient@test.mindtwin.app`
- Password: `password123`

---

## 📚 Full Documentation

For detailed information, see:

- **Flutter App Fixes:** `/mindtwin/IMPLEMENTATION_SUMMARY.md`
- **Backend Setup:** `/mindtwin/BACKEND_SETUP.md`
- **Backend API Docs:** `/mindtwin-backend/README.md`
- **Daily Check-In Code:** `/mindtwin/lib/screens/patient/daily_checkin_screen.dart` (line 262+)
- **Export Feature Code:** `/mindtwin/lib/screens/patient/ethics_control_screen.dart` (line 353+)

---

## ✅ Success Checklist

- [ ] Flutter app runs without errors
- [ ] Rapid Save on Daily Check-In works
- [ ] Data Export button creates JSON file
- [ ] Backend npm packages installed
- [ ] Database migrations complete
- [ ] Backend server running on port 5000
- [ ] Health check curl succeeds
- [ ] Login curl succeeds and returns token
- [ ] Flutter app connects to backend
- [ ] Daily check-in syncs to backend database

Once all checked, your MindTwin system is fully operational! 🎉

---

## Next Steps

1. **For Development:**
   - Keep both Terminal 1 (Flutter) and Terminal 2 (Backend) running
   - Make changes and hot-reload/restart as needed

2. **For Production:**
   - Follow deployment guide in `/mindtwin-backend/README.md`
   - Set proper environment variables
   - Use PostgreSQL instead of SQLite
   - Enable HTTPS/SSL

3. **For Mobile Release:**
   - Use build APK with real backend URL
   - Test on real device
   - Sign APK with release keystore
