# MindTwin Backend Integration Guide

This guide shows how to set up and connect the MindTwin Flutter mobile app to the Node.js/Express backend.

## Backend Setup

### 1. Install Backend Dependencies

```bash
cd mindtwin-backend
npm install
```

### 2. Configure Environment

Create a `.env` file from the example:

```bash
cp .env.example .env
```

Edit `.env` with your settings:
```
PORT=5000
NODE_ENV=development
DATABASE=./mindtwin.db
JWT_SECRET=your_secret_key_here
JWT_EXPIRE=7d
CORS_ORIGIN=http://localhost:3000,http://10.0.2.2:5000
```

**Note:** For Android emulator, use `10.0.2.2` instead of `localhost`

### 3. Run Database Migrations

```bash
npm run migrate
```

This creates the database schema and test users:
- Therapist: `therapist@test.mindtwin.app` / `password123`
- Patient: `patient@test.mindtwin.app` / `password123`

### 4. Start Backend Server

**Development mode (with auto-restart):**
```bash
npm run dev
```

**Production mode:**
```bash
npm start
```

Server will be available at `http://localhost:5000`

Verify with health check:
```bash
curl http://localhost:5000/health
```

## Flutter App Configuration

### Option 1: Build APK with Backend URL

When building the APK, pass the backend URL:

```bash
cd mindtwin
flutter build apk --release \
  --dart-define=MINDTWIN_API_BASE_URL=http://your-backend-url:5000
```

**For Android Emulator:**
```bash
flutter build apk --release \
  --dart-define=MINDTWIN_API_BASE_URL=http://10.0.2.2:5000
```

**For Physical Device:**
```bash
flutter build apk --release \
  --dart-define=MINDTWIN_API_BASE_URL=http://192.168.x.x:5000
```

### Option 2: Run with Development Backend

```bash
cd mindtwin
flutter run --dart-define=MINDTWIN_API_BASE_URL=http://10.0.2.2:5000
```

## Features with Backend

Once connected to the backend, your app gets:

### ✅ Server-Driven Authentication
- User registration and login go through backend
- JWT token-based session management
- Therapist assignment to patients

### ✅ Real-Time Data Sync
- Daily check-ins sync to backend
- Crisis alerts trigger server notifications
- Therapist interventions push to patients
- Messages synchronized between therapist and patient

### ✅ Data Persistence
- All data stored in backend SQLite database
- Therapists can view all assigned patients
- Historical data available across devices

### ✅ Therapist Dashboard
- Access at: API endpoint `/api/therapists/dashboard`
- View all patients and their risk scores
- See pending crisis alerts
- Track recent interventions

## API Test Examples

### User Registration

```bash
curl -X POST http://localhost:5000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newuser@mindtwin.app",
    "password": "secure_password",
    "name": "Test User",
    "role": "patient"
  }'
```

### User Login

```bash
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "therapist@test.mindtwin.app",
    "password": "password123"
  }'
```

Response:
```json
{
  "success": true,
  "userId": "user-id",
  "token": "jwt-token",
  "role": "therapist",
  "name": "Dr. Test Therapist",
  "email": "therapist@test.mindtwin.app"
}
```

### Get Therapist Dashboard (with token)

```bash
curl -X GET http://localhost:5000/api/therapists/dashboard \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Sync Patient Data

```bash
curl -X POST http://localhost:5000/api/sync/patient-data \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "daily_logs": [
      {
        "mood_score": 7,
        "sleep_hours": 8,
        "anxiety_level": 3,
        "wellbeing_score": 75,
        "notes": "Feeling better today"
      }
    ],
    "patient_profile": {
      "risk_score": 0.3,
      "wellbeing_score": 75
    }
  }'
```

## Troubleshooting

### Connection Refused
- Ensure backend server is running: `npm run dev`
- Check port number in `.env` matches Flutter URL
- Verify firewall allows the port

### CORS Errors
- Update `CORS_ORIGIN` in `.env` with your app's domain
- For localhost testing: `CORS_ORIGIN=*`

### Android Emulator Can't Connect
- Use `10.0.2.2` instead of `localhost`
- Ensure no firewall blocking the port
- Test with: `adb shell ping 10.0.2.2`

### Token Errors
- Check JWT_SECRET is set in `.env`
- Verify token wasn't expired (default 7 days)
- Re-login to get new token

### Database Locked
- Close all connections to `mindtwin.db`
- Delete `.db-wal` and `.db-shm` files:
  ```bash
  rm mindtwin.db-wal mindtwin.db-shm
  ```

## Production Deployment

For production, follow these steps:

1. **Set Strong Secrets:**
   ```bash
   JWT_SECRET=$(openssl rand -base64 32)
   ```

2. **Use PostgreSQL** instead of SQLite (recommended)

3. **Deploy on Cloud:**
   - Heroku: `git push heroku main`
   - DigitalOcean: Configure droplet with Node.js
   - AWS: Use ECS or Elastic Beanstalk
   - Google Cloud: Cloud Run

4. **Set HTTPS/SSL** with Let's Encrypt

5. **Configure CORS** for your domain

6. **Set up database backups**

7. **Add monitoring and logging**

## Architecture

```
MindTwin System
├── Flutter Mobile App
│   ├── Local SQLite (offline data)
│   └── Backend API Client
├── Node.js/Express Backend
│   ├── REST API
│   ├── Auth Service
│   ├── Data Sync Service
│   └── SQLite Database
└── Therapist Dashboard
    └── Access via /api endpoints
```

## Support

For issues or questions:
- Check backend logs: `npm run dev` output
- Review Flutter debug console
- Check database with: `sqlite3 mindtwin.db`
- Read API documentation in backend README.md
