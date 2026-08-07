const jwt = require('jsonwebtoken');
const DatabaseService = require('../database/Database');

const authMiddleware = (req, res, next) => {
  try {
    const token = req.headers.authorization?.split(' ')[1];
    
    if (!token) {
      return res.status(401).json({ error: 'Token required' });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.userId = decoded.id || decoded.userId;
    req.userRole = decoded.role;
    next();
  } catch (error) {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
};

const requireRole = (allowedRoles) => {
  return (req, res, next) => {
    if (!allowedRoles.includes(req.userRole)) {
      return res.status(403).json({ error: 'Access denied' });
    }
    next();
  };
};

// Returns true when the authenticated caller may access the given patient record.
// Admin and therapists have access; a patient may only access their own record
// (identified by their Firebase UID or their local patient profile id).
const canAccessPatient = (req, patientId) => {
  if (!patientId) return true;
  if (req.userRole === 'admin') return true;
  if (req.userRole === 'therapist') return true;
  if (patientId === req.userId) return true;
  try {
    const row = DatabaseService.getInstance().getDB()
      .prepare('SELECT id FROM patients WHERE user_id = ?')
      .get(req.userId);
    if (row && row.id === patientId) return true;
  } catch (_) {}
  return false;
};

// Middleware: rejects a patient who tries to access another patient's record.
const requirePatientAccess = (req, res, next) => {
  const patientId = req.params.patientId || req.body.patientId;
  if (patientId && !canAccessPatient(req, patientId)) {
    return res.status(403).json({ error: 'Access denied to this patient record' });
  }
  next();
};

// Middleware: therapist-scoped endpoints must reference the caller's own account.
const requireTherapistSelf = (req, res, next) => {
  const therapistId =
    req.params.therapistId || req.body.therapistId || req.query.therapistId;
  if (therapistId && req.userRole !== 'admin' && req.userId !== therapistId) {
    return res.status(403).json({ error: 'Access denied to this therapist account' });
  }
  next();
};

module.exports = {
  authMiddleware,
  requireRole,
  canAccessPatient,
  requirePatientAccess,
  requireTherapistSelf
};
