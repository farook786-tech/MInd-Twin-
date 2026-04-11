const Database = require('../database/Database');
const ClinicalService = require('./ClinicalService');

/**
 * WearableDataService - Real-time ingestion of wearable health metrics
 * Continuous mood, anxiety, sleep, heart rate streaming
 * Triggers immediate risk factor recalculation (NO batching)
 * All data is REAL from wearables, NO synthetic/random values
 */
class WearableDataService {
  constructor() {
    this.db = new Database();
    this.clinicalService = new ClinicalService();
  }

  /**
   * Ingest real-time mood data from wearable
   * Mood scale: 1 (very sad) to 10 (very happy)
   * Each data point updates patient's real-time mood state
   */
  async recordMoodData(patientId, moodScore, timestamp = null) {
    if (moodScore < 1 || moodScore > 10) {
      throw new Error('Mood score must be between 1 and 10');
    }

    try {
      const recordedAt = timestamp || new Date().toISOString();

      const stmt = this.db.prepare(`
        INSERT INTO wearable_mood_data (
          patient_id,
          mood_score,
          recorded_at
        ) VALUES (?, ?, ?)
      `);

      stmt.run(patientId, moodScore, recordedAt);

      console.log(`[WEARABLE:MOOD] Patient ${patientId}: score=${moodScore} at ${recordedAt}`);

      // Immediately recalculate risk factors with new data
      await this._updateRiskFactorsAfterWearableData(patientId);

      return { success: true, moodScore, timestamp: recordedAt };
    } catch (error) {
      console.error('Record mood data error:', error);
      throw error;
    }
  }

  /**
   * Ingest real-time anxiety data from wearable
   * Anxiety scale: 1 (calm) to 10 (severe anxiety)
   */
  async recordAnxietyData(patientId, anxietyScore, timestamp = null) {
    if (anxietyScore < 1 || anxietyScore > 10) {
      throw new Error('Anxiety score must be between 1 and 10');
    }

    try {
      const recordedAt = timestamp || new Date().toISOString();

      const stmt = this.db.prepare(`
        INSERT INTO wearable_anxiety_data (
          patient_id,
          anxiety_score,
          recorded_at
        ) VALUES (?, ?, ?)
      `);

      stmt.run(patientId, anxietyScore, recordedAt);

      console.log(`[WEARABLE:ANXIETY] Patient ${patientId}: score=${anxietyScore} at ${recordedAt}`);

      // Immediately recalculate risk factors
      await this._updateRiskFactorsAfterWearableData(patientId);

      return { success: true, anxietyScore, timestamp: recordedAt };
    } catch (error) {
      console.error('Record anxiety data error:', error);
      throw error;
    }
  }

  /**
   * Ingest real-time sleep data from wearable
   * Sleep duration in hours (0-12)
   * Sleep quality: 1-10 scale
   */
  async recordSleepData(patientId, sleepDuration, sleepQuality, timestamp = null) {
    if (sleepDuration < 0 || sleepDuration > 12) {
      throw new Error('Sleep duration must be between 0 and 12 hours');
    }
    if (sleepQuality < 1 || sleepQuality > 10) {
      throw new Error('Sleep quality must be between 1 and 10');
    }

    try {
      const recordedAt = timestamp || new Date().toISOString();

      const stmt = this.db.prepare(`
        INSERT INTO wearable_sleep_data (
          patient_id,
          sleep_duration,
          sleep_quality,
          recorded_at
        ) VALUES (?, ?, ?, ?)
      `);

      stmt.run(patientId, sleepDuration, sleepQuality, recordedAt);

      console.log(
        `[WEARABLE:SLEEP] Patient ${patientId}: duration=${sleepDuration}h, quality=${sleepQuality}/10 at ${recordedAt}`,
      );

      // Immediately recalculate risk factors
      await this._updateRiskFactorsAfterWearableData(patientId);

      return { success: true, sleepDuration, sleepQuality, timestamp: recordedAt };
    } catch (error) {
      console.error('Record sleep data error:', error);
      throw error;
    }
  }

  /**
   * Ingest real-time heart rate data from wearable
   * Heart rate in beats per minute
   * resting_heart_rate is used for clinical assessment
   */
  async recordHeartRateData(patientId, heartRate, isResting = false, timestamp = null) {
    if (heartRate < 30 || heartRate > 220) {
      throw new Error('Heart rate must be between 30 and 220 BPM');
    }

    try {
      const recordedAt = timestamp || new Date().toISOString();

      const stmt = this.db.prepare(`
        INSERT INTO wearable_heart_rate_data (
          patient_id,
          heart_rate,
          is_resting,
          recorded_at
        ) VALUES (?, ?, ?, ?)
      `);

      stmt.run(patientId, heartRate, isResting ? 1 : 0, recordedAt);

      const context = isResting ? 'RESTING' : 'ACTIVE';
      console.log(`[WEARABLE:HR] Patient ${patientId}: ${heartRate}bpm (${context}) at ${recordedAt}`);

      // Immediately recalculate risk factors if resting HR (clinical indicator)
      if (isResting) {
        await this._updateRiskFactorsAfterWearableData(patientId);
      }

      return { success: true, heartRate, isResting, timestamp: recordedAt };
    } catch (error) {
      console.error('Record heart rate data error:', error);
      throw error;
    }
  }

  /**
   * Ingest activity data from wearable
   * Steps taken, duration in minutes, calorie burn
   * Low activity contributes to depression symptoms
   */
  async recordActivityData(patientId, steps, activityMinutes, caloriesBurned, timestamp = null) {
    if (steps < 0 || activityMinutes < 0 || caloriesBurned < 0) {
      throw new Error('Activity metrics must be non-negative');
    }

    try {
      const recordedAt = timestamp || new Date().toISOString();

      // Average activity level: <5k steps = low, 5-10k = moderate, >10k = high
      let activityLevel = 'low';
      if (steps >= 10000) activityLevel = 'high';
      else if (steps >= 5000) activityLevel = 'moderate';

      const stmt = this.db.prepare(`
        INSERT INTO wearable_activity_data (
          patient_id,
          steps,
          activity_minutes,
          calories_burned,
          activity_level,
          recorded_at
        ) VALUES (?, ?, ?, ?, ?, ?)
      `);

      stmt.run(patientId, steps, activityMinutes, caloriesBurned, activityLevel, recordedAt);

      console.log(
        `[WEARABLE:ACTIVITY] Patient ${patientId}: ${steps} steps, ${activityMinutes}min, ${caloriesBurned}cal (${activityLevel}) at ${recordedAt}`,
      );

      // Behavioral activation is key CBT intervention for depression
      await this._updateRiskFactorsAfterWearableData(patientId);

      return { success: true, steps, activityMinutes, caloriesBurned, activityLevel, timestamp: recordedAt };
    } catch (error) {
      console.error('Record activity data error:', error);
      throw error;
    }
  }

  /**
   * Batch ingest wearable data (used for syncing from wearable app)
   * All values must be REAL from device, not synthetic
   */
  async ingestWearableBatch(patientId, dataPoints) {
    const results = [];

    try {
      for (const dataPoint of dataPoints) {
        const { type, value, timestamp } = dataPoint;

        switch (type) {
          case 'mood':
            results.push(await this.recordMoodData(patientId, value, timestamp));
            break;
          case 'anxiety':
            results.push(await this.recordAnxietyData(patientId, value, timestamp));
            break;
          case 'sleep':
            results.push(await this.recordSleepData(patientId, value.duration, value.quality, timestamp));
            break;
          case 'heartrate':
            results.push(
              await this.recordHeartRateData(patientId, value.rate, value.isResting, timestamp),
            );
            break;
          case 'activity':
            results.push(
              await this.recordActivityData(patientId, value.steps, value.minutes, value.calories, timestamp),
            );
            break;
        }
      }

      console.log(`[WEARABLE BATCH] Ingested ${results.length} data points for patient ${patientId}`);
      return { success: true, ingested: results.length, results };
    } catch (error) {
      console.error('Ingest wearable batch error:', error);
      return { success: false, error: error.message, ingested: results.length };
    }
  }

  /**
   * Get real-time wearable summary for patient (last 7 days)
   */
  async getWearableSummary(patientId) {
    try {
      const summary = {
        mood: this._getLastSevenDaysMood(patientId),
        anxiety: this._getLastSevenDaysAnxiety(patientId),
        sleep: this._getLastSevenDaysSleep(patientId),
        heartRate: this._getLastSevenDaysHeartRate(patientId),
        activity: this._getLastSevenDaysActivity(patientId),
      };

      return summary;
    } catch (error) {
      console.error('Get wearable summary error:', error);
      return {};
    }
  }

  // Private Methods

  /**
   * Real-time risk factor recalculation after new wearable data
   * This triggers immediate alert generation if thresholds crossed
   */
  async _updateRiskFactorsAfterWearableData(patientId) {
    try {
      // Get last 30 days of wearable data
      const moodData = this.db.prepare(`
        SELECT AVG(mood_score) as avg_mood FROM wearable_mood_data
        WHERE patient_id = ? AND recorded_at > datetime('now', '-30 days')
      `).get(patientId);

      const anxietyData = this.db.prepare(`
        SELECT AVG(anxiety_score) as avg_anxiety FROM wearable_anxiety_data
        WHERE patient_id = ? AND recorded_at > datetime('now', '-30 days')
      `).get(patientId);

      const sleepData = this.db.prepare(`
        SELECT AVG(sleep_duration) as avg_sleep FROM wearable_sleep_data
        WHERE patient_id = ? AND recorded_at > datetime('now', '-30 days')
      `).get(patientId);

      const hrData = this.db.prepare(`
        SELECT AVG(heart_rate) as avg_hr FROM wearable_heart_rate_data
        WHERE patient_id = ? AND is_resting = 1 AND recorded_at > datetime('now', '-30 days')
      `).get(patientId);

      // Calculate risk factors based on real wearable data
      let riskScore = 0;
      const riskFactors = [];

      // Mood assessment (low mood contributes to depression)
      if ((moodData?.avg_mood || 10) < 4) {
        riskScore += 25;
        riskFactors.push(`Low mood trend (avg: ${moodData?.avg_mood?.toFixed(1) || 'N/A'}/10)`);
      }

      // Anxiety assessment
      if ((anxietyData?.avg_anxiety || 1) > 7) {
        riskScore += 20;
        riskFactors.push(`High anxiety trend (avg: ${anxietyData?.avg_anxiety?.toFixed(1) || 'N/A'}/10)`);
      }

      // Sleep assessment (<5 hours indicates sleep disturbance)
      if ((sleepData?.avg_sleep || 8) < 5) {
        riskScore += 20;
        riskFactors.push(`Sleep disturbance (avg: ${sleepData?.avg_sleep?.toFixed(1) || 'N/A'}h)`);
      }

      // Heart rate assessment (elevated RHR indicates stress/anxiety)
      if ((hrData?.avg_hr || 60) > 85) {
        riskScore += 15;
        riskFactors.push(`Elevated resting HR (avg: ${hrData?.avg_hr?.toFixed(0) || 'N/A'} bpm)`);
      }

      // Determine risk level
      let riskLevel = 'low';
      if (riskScore > 60) riskLevel = 'critical';
      else if (riskScore > 40) riskLevel = 'high';
      else if (riskScore > 20) riskLevel = 'moderate';

      // Update clinical_risk_factors table
      const stmt = this.db.prepare(`
        INSERT OR REPLACE INTO clinical_risk_factors (
          patient_id,
          severity_score,
          risk_level,
          risk_factors,
          created_at
        ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
      `);

      stmt.run(patientId, riskScore, riskLevel, JSON.stringify(riskFactors));

      console.log(
        `[RISK RECALCULATION] Patient ${patientId}: score=${riskScore}, level=${riskLevel}, factors=${riskFactors.length}`,
      );

      // If critical risk, create alert immediately
      if (riskLevel === 'critical') {
        await this.clinicalService.createClinicalAlert(
          patientId,
          null, // therapist_id would be looked up
          'critical_risk_factors',
          'critical',
          `Real-time wearable data indicates critical risk factors: ${riskFactors.join(', ')}`,
          riskScore,
          60, // threshold
        );
      }

      return { riskScore, riskLevel, riskFactors };
    } catch (error) {
      console.error('Update risk factors error:', error);
      return null;
    }
  }

  // Data retrieval helpers
  _getLastSevenDaysMood(patientId) {
    return this.db.prepare(`
      SELECT mood_score, recorded_at FROM wearable_mood_data
      WHERE patient_id = ? AND recorded_at > datetime('now', '-7 days')
      ORDER BY recorded_at DESC
    `).all(patientId);
  }

  _getLastSevenDaysAnxiety(patientId) {
    return this.db.prepare(`
      SELECT anxiety_score, recorded_at FROM wearable_anxiety_data
      WHERE patient_id = ? AND recorded_at > datetime('now', '-7 days')
      ORDER BY recorded_at DESC
    `).all(patientId);
  }

  _getLastSevenDaysSleep(patientId) {
    return this.db.prepare(`
      SELECT sleep_duration, sleep_quality, recorded_at FROM wearable_sleep_data
      WHERE patient_id = ? AND recorded_at > datetime('now', '-7 days')
      ORDER BY recorded_at DESC
    `).all(patientId);
  }

  _getLastSevenDaysHeartRate(patientId) {
    return this.db.prepare(`
      SELECT heart_rate, is_resting, recorded_at FROM wearable_heart_rate_data
      WHERE patient_id = ? AND recorded_at > datetime('now', '-7 days')
      ORDER BY recorded_at DESC
    `).all(patientId);
  }

  _getLastSevenDaysActivity(patientId) {
    return this.db.prepare(`
      SELECT steps, activity_minutes, activity_level, recorded_at FROM wearable_activity_data
      WHERE patient_id = ? AND recorded_at > datetime('now', '-7 days')
      ORDER BY recorded_at DESC
    `).all(patientId);
  }

  /**
   * Create wearable tables on first use
   */
  ensureTablesExist() {
    try {
      const tables = [
        `CREATE TABLE IF NOT EXISTS wearable_mood_data (
          id INTEGER PRIMARY KEY,
          patient_id TEXT NOT NULL,
          mood_score INTEGER NOT NULL,
          recorded_at TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (patient_id) REFERENCES patients(id)
        )`,
        `CREATE TABLE IF NOT EXISTS wearable_anxiety_data (
          id INTEGER PRIMARY KEY,
          patient_id TEXT NOT NULL,
          anxiety_score INTEGER NOT NULL,
          recorded_at TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (patient_id) REFERENCES patients(id)
        )`,
        `CREATE TABLE IF NOT EXISTS wearable_sleep_data (
          id INTEGER PRIMARY KEY,
          patient_id TEXT NOT NULL,
          sleep_duration REAL NOT NULL,
          sleep_quality INTEGER NOT NULL,
          recorded_at TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (patient_id) REFERENCES patients(id)
        )`,
        `CREATE TABLE IF NOT EXISTS wearable_heart_rate_data (
          id INTEGER PRIMARY KEY,
          patient_id TEXT NOT NULL,
          heart_rate INTEGER NOT NULL,
          is_resting INTEGER DEFAULT 0,
          recorded_at TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (patient_id) REFERENCES patients(id)
        )`,
        `CREATE TABLE IF NOT EXISTS wearable_activity_data (
          id INTEGER PRIMARY KEY,
          patient_id TEXT NOT NULL,
          steps INTEGER NOT NULL,
          activity_minutes INTEGER NOT NULL,
          calories_burned REAL NOT NULL,
          activity_level TEXT,
          recorded_at TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (patient_id) REFERENCES patients(id)
        )`,
      ];

      for (const sql of tables) {
        this.db.prepare(sql).run();
      }

      console.log('Wearable data tables ensured');
    } catch (error) {
      console.error('Error ensuring wearable tables:', error);
    }
  }
}

module.exports = WearableDataService;
