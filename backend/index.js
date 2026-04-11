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
const mlRoutes    = require('./src/routes/ml');
const geminiRoutes = require('./src/routes/gemini');

const app = express();
const PORT = process.env.PORT || 5000;

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
app.use('/api/ml',   mlRoutes);
app.use('/api/gemini', geminiRoutes);
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
app.listen(PORT, () => {
  console.log(`🚀 MindTwin Backend running on port ${PORT}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV}`);
  console.log(`🔌 Database: ${process.env.DATABASE}`);
});

module.exports = app;
