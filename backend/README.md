# MindTwin Backend

Node.js/Express backend for the MindTwin app.

## What It Does

- Authentication endpoints for register and login
- Patient, therapist, message, alert, sync, clinical, chat, ml, gemini, and realtime routes
- SQLite-backed persistence with a graceful fallback when the optional native database is unavailable

## Install

```powershell
cd backend
npm install
```

## Run

Development:

```powershell
npm run dev
```

Production/local start:

```powershell
npm start
```

Background process options:

```powershell
npm run start:pm2
npm run save:pm2
```

## Environment

Create a `.env` file in `backend/` with values like:

```env
PORT=5000
NODE_ENV=development
DATABASE=./mindtwin.db
CORS_ORIGIN=http://localhost:3000
JWT_SECRET=change-me
JWT_EXPIRE=7d
```

## Health Check

```powershell
Invoke-WebRequest -UseBasicParsing http://localhost:5000/health
```

## Common Endpoints

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `GET /api/patients`
- `GET /api/therapists/dashboard`
- `POST /api/sync/patient-data`
- `GET /api/sync/public/therapist-dashboard`

## Notes

- The backend entry point is `index.js`.
- The backend scripts are defined in `backend/package.json`.
- If you are using Firebase notifications or Admin SDK features, set `GOOGLE_APPLICATION_CREDENTIALS` before starting the server.

## Development

The backend uses:
- **Express.js** - Web framework
- **better-sqlite3** - SQLite database
- **JWT** - Token-based authentication
- **bcryptjs** - Password hashing
- **UUID** - Unique ID generation

## License

MIT
