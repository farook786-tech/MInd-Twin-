#!/usr/bin/env node

/**
 * Migration script for MindTwin backend
 * Creates initial database schema and seed data
 */

require('dotenv').config();
const DatabaseService = require('../src/database/Database');

async function runMigrations() {
  console.log('🔧 Running database migrations...');

  try {
    const db = DatabaseService.getInstance();
    await db.initialize();

    console.log('✅ Database migrations completed successfully!');
    
    // Test data insertion (optional, for development)
    if (process.env.NODE_ENV === 'development') {
      console.log('\n📝 Adding test data...');
      const { v4: uuidv4 } = require('uuid');
      const bcrypt = require('bcryptjs');
      
      const database = db.getDB();

      // Create test therapist
      const therapistId = uuidv4();
      const therapistEmail = 'therapist@test.mindtwin.app';
      const therapistPassword = bcrypt.hashSync('password123', 10);

      try {
        database.prepare(`
          INSERT INTO users (id, email, password_hash, name, role)
          VALUES (?, ?, ?, ?, ?)
        `).run(therapistId, therapistEmail, therapistPassword, 'Dr. Test Therapist', 'therapist');
        console.log(`✅ Test therapist created: ${therapistEmail}`);
      } catch (e) {
        if (e.message.includes('UNIQUE')) {
          console.log(`⚠️  Test therapist already exists: ${therapistEmail}`);
        }
      }

      // Create test patient
      const patientId = uuidv4();
      const patientUserId = uuidv4();
      const patientEmail = 'patient@test.mindtwin.app';
      const patientPassword = bcrypt.hashSync('password123', 10);

      try {
        database.prepare(`
          INSERT INTO users (id, email, password_hash, name, role)
          VALUES (?, ?, ?, ?, ?)
        `).run(patientUserId, patientEmail, patientPassword, 'John Patient', 'patient');
        
        database.prepare(`
          INSERT INTO patients (id, user_id, therapist_id, age)
          VALUES (?, ?, ?, ?)
        `).run(patientId, patientUserId, therapistId, 28);

        database.prepare(`
          INSERT INTO privacy_settings (id, user_id)
          VALUES (?, ?)
        `).run(uuidv4(), patientUserId);

        console.log(`✅ Test patient created: ${patientEmail}`);
      } catch (e) {
        if (e.message.includes('UNIQUE')) {
          console.log(`⚠️  Test patient already exists: ${patientEmail}`);
        }
      }

      console.log('\n📋 Test Data:');
      console.log(`  Therapist: ${therapistEmail} / password123`);
      console.log(`  Patient: ${patientEmail} / password123`);
    }

    db.close();
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

runMigrations();
