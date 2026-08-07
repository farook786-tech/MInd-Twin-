require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const Database = require('./src/database/Database');
const authRoutes = require('./src/routes/auth');
const patientRoutes = require('./src/routes/patients');
const therapistRoutes = require('./src/routes/therapists');
const messageRoutes = require('./src/routes/messages');
const alertRoutes = require('./src/routes/alerts');
const syncRoutes = require('./src/routes/sync');
const clinicalRoutes = require('./src/routes/clinical');
const realtimeRoutes = require('./src/routes/realtime');
const chatRoutes = require('./src/routes/chat');

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
app.use(cors({
  origin: function(origin, callback) {
    callback(null, true);
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));
app.options('*', cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ limit: '50mb', extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// Initialize database
const db = Database.getInstance();
db.initialize().catch(err => {
  console.warn('Database initialization failed; continuing without SQLite:', err);
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/patients', patientRoutes);
app.use('/api/therapists', therapistRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/alerts', alertRoutes);
app.use('/api/sync', syncRoutes);
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
