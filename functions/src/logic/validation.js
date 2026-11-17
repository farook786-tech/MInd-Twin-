'use strict';

class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ValidationError';
  }
}

// Control characters (incl. NUL, newlines) are rejected in names.
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;

function requireObject(data) {
  if (data === undefined || data === null) return {};
  if (typeof data !== 'object' || Array.isArray(data)) {
    throw new ValidationError('Request data must be an object.');
  }
  return data;
}

function validateName(raw) {
  if (typeof raw !== 'string') throw new ValidationError('name is required.');
  const name = raw.trim().replace(/\s+/g, ' ');
  if (name.length < 1 || name.length > 100) {
    throw new ValidationError('name must be 1-100 characters.');
  }
  if (CONTROL_CHARS.test(name)) throw new ValidationError('name contains invalid characters.');
  return name;
}

function validateOptionalText(raw, field, maxLen) {
  if (raw === undefined || raw === null || raw === '') return null;
  if (typeof raw !== 'string') throw new ValidationError(`${field} must be a string.`);
  const v = raw.trim();
  if (v.length > maxLen) throw new ValidationError(`${field} must be at most ${maxLen} characters.`);
  if (CONTROL_CHARS.test(v)) throw new ValidationError(`${field} contains invalid characters.`);
  return v.length ? v : null;
}

function validateUid(raw, field) {
  if (typeof raw !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(raw)) {
    throw new ValidationError(`${field} must be a valid user id.`);
  }
  return raw;
}

module.exports = {
  ValidationError,
  requireObject,
  validateName,
  validateOptionalText,
  validateUid,
};
