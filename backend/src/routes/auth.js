const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const DatabaseService = require('../database/Database');
const { authMiddleware } = require('../middleware/auth');

const router = express.Router();
const db = DatabaseService.getInstance();

// Generate JWT token
const generateToken = (userId, role) => {
  return jwt.sign(
    { id: userId, role },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRE || '7d' }
  );
};

// Register user (PATIENT ONLY - no role selection from app)
router.post('/register', (req, res) => {
  try {
    const { email, password, name } = req.body;

    if (!email || !password || !name) {
      return res.status(400).json({ error: 'Email, password, and name required' });
    }

    const userId = uuidv4();
    const passwordHash = bcrypt.hashSync(password, 10);

    const database = db.getDB();
    const stmt = database.prepare(`
      INSERT INTO users (id, email, password_hash, name, role)
      VALUES (?, ?, ?, ?, ?)
    `);

    // SECURITY: Always register as patient - no role parameter accepted
    stmt.run(userId, email.toLowerCase(), passwordHash, name, 'patient');

    // Create patient profile
    const patientStmt = database.prepare(`
      INSERT INTO patients (id, user_id)
      VALUES (?, ?)
    `);
    patientStmt.run(uuidv4(), userId);

    // Create privacy settings
    const privacyStmt = database.prepare(`
      INSERT INTO privacy_settings (id, user_id)
      VALUES (?, ?)
    `);
    privacyStmt.run(uuidv4(), userId);

    const token = generateToken(userId, 'patient');

    res.status(201).json({
      success: true,
      userId,
      token,
      role: 'patient',
      message: 'Registration successful'
    });
  } catch (error) {
    console.error('Registration error:', error);
    if (error.message.includes('UNIQUE constraint failed')) {
      return res.status(409).json({ error: 'Email already exists' });
    }
    res.status(500).json({ error: error.message });
  }
});

// Login user
router.post('/login', (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password required' });
    }

    const database = db.getDB();
    const user = database.prepare(`
      SELECT * FROM users WHERE email = ?
    `).get(email.toLowerCase());

    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Firebase-backed accounts authenticate through Firebase, not passwords.
    if (user.auth_provider === 'firebase') {
      return res.status(401).json({ error: 'This account uses Firebase sign-in. Please sign in from the app.' });
    }

    const validPassword = bcrypt.compareSync(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = generateToken(user.id, user.role);

    res.json({
      success: true,
      userId: user.id,
      token,
      role: user.role,
      name: user.name,
      email: user.email
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get current user
router.get('/me', authMiddleware, (req, res) => {
  try {
    const database = db.getDB();
    const user = database.prepare(`
      SELECT id, email, name, role, created_at FROM users WHERE id = ?
    `).get(req.userId);

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ user });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Verify token
router.post('/verify', authMiddleware, (req, res) => {
  res.json({ valid: true, userId: req.userId, role: req.userRole });
});

// ADMIN ONLY: Register therapist (requires authentication)
router.post('/register-therapist', authMiddleware, (req, res) => {
  try {
    // SECURITY: Only admins or therapists can create new therapist accounts
    // For now, restrict to existing therapists (can be changed to admin-only later)
    if (req.userRole !== 'therapist' && req.userRole !== 'admin') {
      return res.status(403).json({ error: 'Unauthorized: Only therapists and admins can register new therapists' });
    }

    const { email, password, name } = req.body;

    if (!email || !password || !name) {
      return res.status(400).json({ error: 'Email, password, and name required' });
    }

    const userId = uuidv4();
    const passwordHash = bcrypt.hashSync(password, 10);

    const database = db.getDB();
    
    // Check if email already exists
    const existingUser = database.prepare(`
      SELECT id FROM users WHERE email = ?
    `).get(email.toLowerCase());

    if (existingUser) {
      return res.status(409).json({ error: 'Email already exists' });
    }

    const stmt = database.prepare(`
      INSERT INTO users (id, email, password_hash, name, role)
      VALUES (?, ?, ?, ?, ?)
    `);

    // SECURITY: Force role as therapist (no user input)
    stmt.run(userId, email.toLowerCase(), passwordHash, name, 'therapist');

    const token = generateToken(userId, 'therapist');

    res.status(201).json({
      success: true,
      userId,
      token,
      role: 'therapist',
      message: 'Therapist account created successfully',
      registeredBy: req.userId
    });
  } catch (error) {
    console.error('Therapist registration error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Firebase Token Exchange & Account Sync Endpoint
router.post('/firebase-sync', (req, res) => {
  try {
    const { uid, email, name, role } = req.body;

    if (!uid || !email) {
      return res.status(400).json({ error: 'Firebase uid and email required' });
    }

    const database = db.getDB();

    // SECURITY: Never trust a client-supplied role for privilege escalation.
    // New accounts may only be provisioned as 'patient' or 'therapist'
    // (never 'admin'), and existing accounts never change role through sync.
    const allowedRoles = new Set(['patient', 'therapist']);
    const requestedRole = allowedRoles.has(role) ? role : 'patient';

    let user = database.prepare('SELECT * FROM users WHERE id = ? OR email = ?').get(uid, email.toLowerCase());

    if (!user) {
      // Create user record for Firebase user in local DB if not present.
      // Use a random unguessable password so the deterministic
      // bcrypt(uid + '_firebase_secret') backdoor cannot be used to log in.
      const passwordHash = bcrypt.hashSync(crypto.randomBytes(32).toString('hex'), 10);
      const stmt = database.prepare(`
        INSERT INTO users (id, email, password_hash, name, role, auth_provider)
        VALUES (?, ?, ?, ?, ?, 'firebase')
      `);
      stmt.run(uid, email.toLowerCase(), passwordHash, name || email.split('@')[0], requestedRole);

      const patientStmt = database.prepare('INSERT INTO patients (id, user_id) VALUES (?, ?)');
      patientStmt.run(uuidv4(), uid);

      const privacyStmt = database.prepare('INSERT INTO privacy_settings (id, user_id) VALUES (?, ?)');
      privacyStmt.run(uuidv4(), uid);

      user = { id: uid, email: email.toLowerCase(), role: requestedRole, name: name || email.split('@')[0] };
    }

    // Never allow a client to escalate an existing account's role.
    if (!allowedRoles.has(user.role)) {
      return res.status(403).json({ error: 'Account role cannot be provisioned through sync' });
    }

    const token = generateToken(user.id, user.role);

    res.json({
      success: true,
      token,
      userId: user.id,
      role: user.role,
      name: user.name,
      email: user.email
    });
  } catch (error) {
    console.error('Firebase sync error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

