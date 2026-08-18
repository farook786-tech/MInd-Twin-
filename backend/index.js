require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const Database = require('./src/database/Database');
const WearableDataService = require('./src/services/WearableDataService');
const EngagementReminderService = require('./src/services/EngagementReminderService');
const authRoutes = require('./src/routes/auth');
const patientRoutes = require('./src/routes/patients');
const therapistRoutes = require('./src/routes/therapists');
const messageRoutes = require('./src/routes/messages');
const alertRoutes = require('./src/routes/alerts');
const syncRoutes = require('./src/routes/sync');
const usersRoutes = require('./src/routes/users');
const clinicalRoutes = require('./src/routes/clinical');
const realtimeRoutes = require('./src/routes/realtime');
const chatRoutes = require('./src/routes/chat');
const TokenBucketMiddleware = require('./src/middleware/TokenBucketMiddleware');

let mlRoutes = null;
let geminiRoutes = null;

try {
  mlRoutes = require('./src/routes/ml');
} catch (error) {
  console.warn('[Backend] Optional ML routes not available:', error.message);
}

try {
  geminiRoutes = require('./src/routes/gemini');
} catch (error) {
  console.warn('[Backend] Optional Gemini routes not available:', error.message);
}

const app = express();
const BASE_PORT = Number(process.env.PORT || 5000);
const MAX_PORT_ATTEMPTS = 20;

// Middleware
const allowedOrigins = (process.env.CORS_ORIGIN || 'http://localhost:3000,http://127.0.0.1:8080,http://localhost:8080')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

app.use(cors({
  origin: function(origin, callback) {
    // Allow same-origin / non-browser requests and configured origins only.
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));
app.options('*', cors());
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ limit: '10mb', extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// Initialize database
const db = Database.getInstance();
db.initialize()
  .then(() => {
    // Service tables (wearable + engagement) are created after the main schema
    // so their FK references to `patients` already exist.
    try {
      new WearableDataService().ensureTablesExist();
    } catch (error) {
      console.warn('[Backend] Wearable tables not ensured:', error.message);
    }
    try {
      new EngagementReminderService().ensureTablesExist();
    } catch (error) {
      console.warn('[Backend] Engagement tables not ensured:', error.message);
    }
  })
  .catch(err => {
    console.warn('Database initialization failed; continuing without SQLite:', err);
  });

// Rate limiting
// Auth endpoints are unauthenticated, so the limiter keys on client IP.
// AI routes (/api/ml, /api/gemini) apply a per-user limiter after their
// JWT auth middleware inside the route files.
const authRateLimit = TokenBucketMiddleware({ capacity: 10, windowMs: 60 * 1000 });

// Routes
app.use('/api/auth', authRateLimit);
app.use('/api/auth', authRoutes);
app.use('/api/patients', patientRoutes);
app.use('/api/therapists', therapistRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/alerts', alertRoutes);
app.use('/api/sync', syncRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/clinical', clinicalRoutes);
app.use('/api/chat', chatRoutes);
if (mlRoutes) app.use('/api/ml', mlRoutes);
if (geminiRoutes) app.use('/api/gemini', geminiRoutes);
app.use('/api/realtime', realtimeRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    error: err.message || 'Internal server error',
    timestamp: new Date().toISOString()
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Route not found',
    path: req.path
  });
});

// Start server
const startServer = (port = BASE_PORT, attempt = 1) => {
  const server = app.listen(port, () => {
    console.log(`🚀 MindTwin Backend running on port ${port}`);
    console.log(`📊 Environment: ${process.env.NODE_ENV}`);
    console.log(`🔌 Database: ${process.env.DATABASE}`);
  });

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      if (attempt >= MAX_PORT_ATTEMPTS) {
        console.error(`[Backend] Port ${port} is busy and no free port was found after ${MAX_PORT_ATTEMPTS} attempts.`);
        process.exit(1);
        return;
      }

      const nextPort = port + 1;
      console.warn(`[Backend] Port ${port} is already in use. Trying ${nextPort}...`);
      if (server.listening) {
        server.close(() => startServer(nextPort, attempt + 1));
      } else {
        startServer(nextPort, attempt + 1);
      }
    } else {
      console.error('[Backend] Failed to start server:', err);
      process.exit(1);
    }
  });
};

startServer();

module.exports = app;
