# MindTwin Backend

Express.js server for MindTwin mental health platform with SQLite database for therapist-patient data sync.

## Features

- **Authentication**: JWT-based user registration and login
- **Patient Management**: Create, update, and track patient profiles
- **Daily Logs**: Store and retrieve patient daily check-in data
- **Crisis Alerts**: Manage mental health crisis alerts and interventions
- **Messaging**: Real-time conversation between therapists and patients
- **Data Sync**: Bidirectional sync between mobile app and backend
- **Therapist Dashboard**: View all assigned patients and their status

## Requirements

- Node.js 20.x or higher (Node 22 supported)
- npm or yarn

## Installation

1. **Clone backend files:**
   ```bash
   cd mindtwin-backend
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Create .env file:**
   ```bash
   cp .env.example .env
   ```

4. **Configure environment (edit .env):**
   ```env
   PORT=5000
   NODE_ENV=development
   DATABASE=./mindtwin.db
   JWT_SECRET=your_super_secret_key_change_in_production
   JWT_EXPIRE=7d
   CORS_ORIGIN=http://localhost:3000
   ```

## Running the Server

**Development (with auto-restart):**
```bash
npm run dev
```

**Production:**
```bash
npm start
```

**Always-on background mode (recommended for therapist-patient sharing):**
```bash
npm run start:pm2
npm run save:pm2
```

**Windows quick scripts (from backend folder):**
```bat
run_persistent.bat
stop_persistent.bat
```

Useful PM2 commands:
```bash
npm run logs:pm2
npm run restart:pm2
npm run stop:pm2
```

## Always-On Cloud Deployment (Render)

This project now includes deployment files for Render:
- `render.yaml` (at project root)
- `backend/Dockerfile`
- `backend/.dockerignore`

### Why cloud deployment
- Your app keeps working even if your laptop is off.
- Chat, shared appointments, and sync stay available 24/7.

### Steps
1. Push your latest code to GitHub.
2. In Render, create a new Blueprint service from your GitHub repo.
3. Render auto-detects `render.yaml` and creates `mindtwin-backend`.
4. Set secret env vars in Render dashboard:
   - `JWT_SECRET` (required)
   - `CORS_ORIGIN` (required for web, for example `https://your-web-domain.com`)
5. Deploy and wait for health check to pass (`/health`).
6. Copy your Render URL, for example `https://mindtwin-backend.onrender.com`.

### Flutter build with cloud backend
```bash
flutter build apk --dart-define=APP_MODE=patient --dart-define=MINDTWIN_API_BASE_URL=https://mindtwin-backend.onrender.com --dart-define=MINDTWIN_CLINIC_CODE=CLINIC001
flutter build apk --dart-define=APP_MODE=therapist --dart-define=MINDTWIN_API_BASE_URL=https://mindtwin-backend.onrender.com --dart-define=MINDTWIN_CLINIC_CODE=CLINIC001
flutter build web --release --dart-define=MINDTWIN_API_BASE_URL=https://mindtwin-backend.onrender.com --dart-define=MINDTWIN_CLINIC_CODE=CLINIC001
```

### Notes
- `DATABASE` is configured to `/var/data/mindtwin.db` via `render.yaml`.
- Render disk storage is persistent for SQLite, but PostgreSQL is recommended for larger production scale.

The server will start on `http://localhost:5000` (or your configured PORT)

Health check: `GET http://localhost:5000/health`

## API Endpoints

### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login user
- `GET /api/auth/me` - Get current user (requires token)
- `POST /api/auth/verify` - Verify JWT token

### Patients
- `GET /api/patients` - Get all patients (therapist only)
- `GET /api/patients/:patientId` - Get patient details
- `PUT /api/patients/:patientId` - Update patient data
- `GET /api/patients/:patientId/daily-logs` - Get daily logs
- `POST /api/patients/:patientId/daily-logs` - Add daily log
- `GET /api/patients/:patientId/alerts` - Get crisis alerts
- `POST /api/patients/:patientId/alerts` - Create crisis alert

### Therapists
- `GET /api/therapists/dashboard` - Get therapist dashboard (therapist only)
- `PUT /api/therapists/alerts/:alertId/resolve` - Resolve alert
- `POST /api/therapists/interventions` - Create intervention

### Messages
- `GET /api/messages/conversations` - Get all conversations
- `GET /api/messages/conversations/:conversationId` - Get conversation messages
- `POST /api/messages/conversations/:conversationId/messages` - Send message
- `POST /api/messages/conversations` - Create or get conversation

### Alerts
- `GET /api/alerts` - Get all alerts
- `GET /api/alerts/:alertId` - Get alert details
- `PATCH /api/alerts/:alertId` - Update alert

### Sync
- `POST /api/sync/patient-data` - Sync patient data from mobile app
- `GET /api/sync/pull` - Get updates for mobile app
- `POST /api/sync/public/checkin` - Public clinic-code check-in sync (patient app)
- `GET /api/sync/public/therapist-dashboard?clinicCode=...` - Therapist cloud dashboard feed

## Example Requests

### Register User
```bash
curl -X POST http://localhost:5000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "doctor@mindtwin.app",
    "password": "secure_password",
    "name": "Dr. Smith",
    "role": "therapist"
  }'
```

### Login
```bash
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "doctor@mindtwin.app",
    "password": "secure_password"
  }'
```

### Get Patient Dashboard (with token)
```bash
curl -X GET http://localhost:5000/api/therapists/dashboard \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## Database Schema

The SQLite database includes the following tables:
- `users` - User accounts (therapists, patients)
- `patients` - Patient profiles
- `daily_logs` - Daily check-in responses
- `crisis_alerts` - Mental health crisis alerts
- `messages` - Chat messages
- `conversations` - Message conversations
- `voice_journals` - Voice journal entries
- `interventions` - Therapist interventions
- `privacy_settings` - User privacy preferences
- `device_tokens` - Push notification tokens

## Mobile App Integration

1. **Update backend URL in Flutter app:**
   - Set `MINDTWIN_API_BASE_URL` environment variable to your backend URL
   - Set `MINDTWIN_CLINIC_CODE` to the same value on patient and therapist builds
   - Example: `MINDTWIN_API_BASE_URL=http://localhost:5000`

Example build commands:
```bash
flutter build apk --dart-define=APP_MODE=patient --dart-define=MINDTWIN_API_BASE_URL=http://YOUR_IP:5000 --dart-define=MINDTWIN_CLINIC_CODE=CLINIC001
flutter build apk --dart-define=APP_MODE=unified --dart-define=MINDTWIN_API_BASE_URL=http://YOUR_IP:5000 --dart-define=MINDTWIN_CLINIC_CODE=CLINIC001
```

2. **Flutter app will automatically:**
   - Use backend for authentication and data storage
   - Sync daily check-ins to backend
   - Receive real-time updates from therapist
   - Store local copy of data for offline access

3. **Build app with backend:**
   ```bash
   cd /mindtwin
   flutter build apk --release --dart-define=MINDTWIN_API_BASE_URL=http://your-backend:5000
   ```

## Production Deployment

For production deployment:

1. **Use strong JWT_SECRET:**
   ```bash
   openssl rand -base64 32
   ```

2. **Use PostgreSQL instead of SQLite** (recommended for production)

3. **Set up CORS properly:**
   ```env
   CORS_ORIGIN=https://yourdomain.com
   ```

4. **Use HTTPS/SSL**

5. **Add rate limiting and authentication headers**

6. **Set up database backups**

## Troubleshooting

**Port already in use:**
```bash
PORT=5001 npm start
```

**Database locked:**
```bash
rm mindtwin.db-wal mindtwin.db-shm
```

**JWT errors:**
- Check that JWT_SECRET is set correctly
- Verify token hasn't expired
- Ensure Authorization header format: `Bearer YOUR_TOKEN`

## Development

The backend uses:
- **Express.js** - Web framework
- **better-sqlite3** - SQLite database
- **JWT** - Token-based authentication
- **bcryptjs** - Password hashing
- **UUID** - Unique ID generation

## License

MIT
