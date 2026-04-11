const PDFDocument = require('pdfkit');
const Database = require('../database/Database');
const fs = require('fs');
const path = require('path');

/**
 * PDFReportService - Generate clinical PDF reports for treatment outcomes
 * Creates hospital-grade reports with:
 * - PHQ-9 score trajectory
 * - Treatment response metrics
 * - Risk factor analysis
 * - Evidence-based recommendations
 * All data based on actual collected metrics (NO random values)
 */
class PDFReportService {
  constructor() {
    this.db = new Database();
    this.reportsDir = path.join(__dirname, '../../reports');
    this._ensureReportsDirectory();
  }

  /**
   * Generate comprehensive treatment outcome report
   */
  async generateTreatmentOutcomeReport(patientId, therapistId) {
    try {
      // Gather all clinical data
      const patient = this.db.prepare('SELECT * FROM patients WHERE id = ?').get(patientId);
      const therapist = this.db.prepare('SELECT * FROM users WHERE id = ?').get(therapistId);

      const assessmentHistory = this.db.prepare(`
        SELECT * FROM phq9_assessments
        WHERE patient_id = ?
        ORDER BY assessment_date ASC
      `).all(patientId);

      const treatmentResponse = this.db.prepare(`
        SELECT * FROM treatment_responses
        WHERE patient_id = ?
        ORDER BY created_at DESC LIMIT 1
      `).get(patientId);

      const riskFactors = this.db.prepare(`
        SELECT * FROM clinical_risk_factors
        WHERE patient_id = ?
        ORDER BY created_at DESC LIMIT 1
      `).get(patientId);

      const interventions = this.db.prepare(`
        SELECT * FROM intervention_recommendations
        WHERE patient_id = ?
        ORDER BY created_at DESC
      `).all(patientId);

      // Create PDF
      const doc = new PDFDocument({ margin: 50 });
      const filename = `treatment_report_${patientId}_${Date.now()}.pdf`;
      const filepath = path.join(this.reportsDir, filename);

      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      // Header
      this._addReportHeader(doc, patient, therapist);

      // Summary Section
      this._addSummarySection(doc, patient, assessmentHistory, treatmentResponse);

      // PHQ-9 Trajectory
      this._addPHQ9TrajectorySection(doc, assessmentHistory);

      // Treatment Response Metrics
      if (treatmentResponse) {
        this._addTreatmentResponseSection(doc, treatmentResponse);
      }

      // Risk Factors Analysis
      if (riskFactors) {
        this._addRiskFactorsSection(doc, riskFactors);
      }

      // Current Treatment Plan
      if (interventions.length > 0) {
        this._addInterventionsSection(doc, interventions);
      }

      // Recommendations
      this._addRecommendationsSection(doc, treatmentResponse, riskFactors);

      // Footer
      this._addReportFooter(doc);

      doc.end();

      return new Promise((resolve, reject) => {
        stream.on('finish', () => {
          console.log(`Report generated: ${filename}`);
          resolve({ success: true, filename, filepath });
        });
        stream.on('error', reject);
      });
    } catch (error) {
      console.error('Generate report error:', error);
      throw error;
    }
  }

  /**
   * Generate simple progress report (for patient/therapist quick view)
   */
  async generateProgressReport(patientId) {
    try {
      const patient = this.db.prepare('SELECT * FROM patients WHERE id = ?').get(patientId);

      const assessments = this.db.prepare(`
        SELECT id, score, severity, assessment_date, is_baseline
        FROM phq9_assessments
        WHERE patient_id = ?
        ORDER BY assessment_date DESC LIMIT 5
      `).all(patientId);

      const doc = new PDFDocument({ margin: 30 });
      const filename = `progress_report_${patientId}_${Date.now()}.pdf`;
      const filepath = path.join(this.reportsDir, filename);

      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      // Header
      doc.fontSize(24).font('Helvetica-Bold').text('Treatment Progress Report', { align: 'center' });
      doc.fontSize(10).font('Helvetica').text(`Generated: ${new Date().toLocaleDateString()}`, {
        align: 'center',
      });
      doc.moveDown();

      // Patient Info
      doc.fontSize(12).font('Helvetica-Bold').text('Patient Information');
      doc.fontSize(10);
      doc.text(`Name: ${patient?.name || 'N/A'}`);
      doc.text(`Email: ${patient?.email || 'N/A'}`);
      doc.text(`Patient ID: ${patientId}`);
      doc.moveDown();

      // Assessment History
      doc.fontSize(12).font('Helvetica-Bold').text('Recent PHQ-9 Assessments');
      doc.fontSize(9).font('Helvetica');

      assessments.forEach((assessment, index) => {
        const date = new Date(assessment.assessment_date).toLocaleDateString();
        const baseline = assessment.is_baseline ? ' [BASELINE]' : '';
        doc.text(`${index + 1}. Score: ${assessment.score}/27 (${assessment.severity})${baseline} - ${date}`);
      });

      doc.moveDown();
      doc.fontSize(10).text('For detailed clinical analysis, consult with your therapist.', {
        align: 'center',
        italics: true,
      });

      doc.end();

      return new Promise((resolve, reject) => {
        stream.on('finish', () => {
          console.log(`Progress report generated: ${filename}`);
          resolve({ success: true, filename, filepath });
        });
        stream.on('error', reject);
      });
    } catch (error) {
      console.error('Generate progress report error:', error);
      throw error;
    }
  }

  /**
   * Generate wearable data summary report
   */
  async generateWearableDataReport(patientId, days = 30) {
    try {
      const patient = this.db.prepare('SELECT * FROM patients WHERE id = ?').get(patientId);

      const moodData = this.db.prepare(`
        SELECT AVG(mood_score) as avg_mood, MIN(mood_score) as min_mood, MAX(mood_score) as max_mood
        FROM wearable_mood_data
        WHERE patient_id = ? AND recorded_at > datetime('now', ? || ' days')
      `).get(patientId, `-${days}`);

      const anxietyData = this.db.prepare(`
        SELECT AVG(anxiety_score) as avg_anxiety, MIN(anxiety_score) as min_anxiety, MAX(anxiety_score) as max_anxiety
        FROM wearable_anxiety_data
        WHERE patient_id = ? AND recorded_at > datetime('now', ? || ' days')
      `).get(patientId, `-${days}`);

      const sleepData = this.db.prepare(`
        SELECT AVG(sleep_duration) as avg_sleep, AVG(sleep_quality) as avg_quality
        FROM wearable_sleep_data
        WHERE patient_id = ? AND recorded_at > datetime('now', ? || ' days')
      `).get(patientId, `-${days}`);

      const doc = new PDFDocument({ margin: 30 });
      const filename = `wearable_report_${patientId}_${Date.now()}.pdf`;
      const filepath = path.join(this.reportsDir, filename);

      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      // Header
      doc.fontSize(20).font('Helvetica-Bold').text('Wearable Data Summary Report', { align: 'center' });
      doc.fontSize(9).font('Helvetica').text(`Patient: ${patient?.name} | Period: Last ${days} Days`, {
        align: 'center',
      });
      doc.moveDown();

      // Mood Summary
      doc.fontSize(11).font('Helvetica-Bold').text('Mood Tracking');
      doc.fontSize(9).font('Helvetica');
      if (moodData) {
        doc.text(`Average Mood: ${(moodData.avg_mood || 0).toFixed(1)}/10`);
        doc.text(`Mood Range: ${moodData.min_mood} (low) to ${moodData.max_mood} (high)`);
        doc.text('Interpretation: ' + this._interpretMood(moodData.avg_mood));
      } else {
        doc.text('No mood data recorded');
      }
      doc.moveDown();

      // Anxiety Summary
      doc.fontSize(11).font('Helvetica-Bold').text('Anxiety Levels');
      doc.fontSize(9).font('Helvetica');
      if (anxietyData) {
        doc.text(`Average Anxiety: ${(anxietyData.avg_anxiety || 0).toFixed(1)}/10`);
        doc.text(`Anxiety Range: ${anxietyData.min_anxiety} (calm) to ${anxietyData.max_anxiety} (severe)`);
        doc.text('Interpretation: ' + this._interpretAnxiety(anxietyData.avg_anxiety));
      } else {
        doc.text('No anxiety data recorded');
      }
      doc.moveDown();

      // Sleep Summary
      doc.fontSize(11).font('Helvetica-Bold').text('Sleep Quality');
      doc.fontSize(9).font('Helvetica');
      if (sleepData) {
        doc.text(`Average Sleep Duration: ${(sleepData.avg_sleep || 0).toFixed(1)} hours`);
        doc.text(`Sleep Quality Score: ${(sleepData.avg_quality || 0).toFixed(1)}/10`);
        doc.text('Interpretation: ' + this._interpretSleep(sleepData.avg_sleep));
      } else {
        doc.text('No sleep data recorded');
      }
      doc.moveDown();

      // Clinical Notes
      doc.fontSize(9).italics().text(
        'Note: This report is based on real-time wearable device data. '
        + 'Discuss trends with your therapist for personalized interventions.',
      );

      doc.end();

      return new Promise((resolve, reject) => {
        stream.on('finish', () => {
          console.log(`Wearable report generated: ${filename}`);
          resolve({ success: true, filename, filepath });
        });
        stream.on('error', reject);
      });
    } catch (error) {
      console.error('Generate wearable report error:', error);
      throw error;
    }
  }

  // Private Helper Methods

  _addReportHeader(doc, patient, therapist) {
    doc.fontSize(28).font('Helvetica-Bold').text('TREATMENT OUTCOME REPORT', { align: 'center' });
    doc.moveDown(0.5);

    doc.fontSize(10)
      .font('Helvetica')
      .text('Hospital-Grade Clinical Assessment & Treatment Tracking', { align: 'center' });
    doc.fontSize(9).text(`Generated: ${new Date().toLocaleDateString()}`, { align: 'center' });

    doc.moveTo(50, doc.y).lineTo(550, doc.y).stroke();
    doc.moveDown();

    // Patient & Therapist Info
    doc.fontSize(11).font('Helvetica-Bold').text('Patient Information');
    doc.fontSize(9).font('Helvetica');
    doc.text(`Name: ${patient?.name || 'N/A'}`);
    doc.text(`Email: ${patient?.email || 'N/A'}`);
    doc.text(`Patient ID: ${patient?.id || 'N/A'}`);
    doc.moveDown();

    if (therapist) {
      doc.fontSize(11).font('Helvetica-Bold').text('Treating Therapist');
      doc.fontSize(9).font('Helvetica');
      doc.text(`Name: ${therapist?.name || 'N/A'}`);
      doc.text(`Clinic: ${therapist?.clinic_code || 'N/A'}`);
      doc.moveDown();
    }
  }

  _addSummarySection(doc, patient, assessmentHistory, treatmentResponse) {
    doc.fontSize(14).font('Helvetica-Bold').text('Executive Summary');
    doc.moveDown(0.3);

    const baselineAssessment = assessmentHistory.find((a) => a.is_baseline);
    const currentAssessment = assessmentHistory[assessmentHistory.length - 1];

    if (baselineAssessment && currentAssessment && treatmentResponse) {
      const responsePercentage = treatmentResponse.response_percentage || 0;
      const remissionStatus = treatmentResponse.remission_status || 'no_data';

      doc.fontSize(10).font('Helvetica');

      if (remissionStatus === 'remission') {
        doc.text(
          `✓ ${patient?.name} has achieved REMISSION from major depressive disorder.`,
        );
        doc.text(`  PHQ-9 score improved from ${baselineAssessment.score} to ${currentAssessment.score} (${responsePercentage}% improvement).`);
      } else if (remissionStatus === 'significant_progress') {
        doc.text(
          `✓ ${patient?.name} is demonstrating SIGNIFICANT PROGRESS in treatment.`,
        );
        doc.text(`  PHQ-9 score improved by ${responsePercentage}% over ${treatmentResponse.weeks_since_baseline} weeks.`);
      } else {
        doc.text(
          `→ ${patient?.name} is in treatment. Current PHQ-9 score: ${currentAssessment.score}.`,
        );
        doc.text(`  Response rate: ${responsePercentage}% after ${treatmentResponse.weeks_since_baseline} weeks.`);
      }

      doc.moveDown();
    }
  }

  _addPHQ9TrajectorySection(doc, assessmentHistory) {
    doc.fontSize(14).font('Helvetica-Bold').text('PHQ-9 Score Trajectory');
    doc.moveDown(0.3);

    doc.fontSize(9).font('Helvetica');
    doc.text('Assessment History (0-27 scale, lower is better):');
    doc.moveDown(0.2);

    const tableTop = doc.y;
    const col1X = 60;
    const col2X = 200;
    const col3X = 350;
    const col4X = 480;
    const rowHeight = 20;

    // Header
    doc.font('Helvetica-Bold').fontSize(9);
    doc.text('Date', col1X, tableTop);
    doc.text('Score', col2X, tableTop);
    doc.text('Severity', col3X, tableTop);
    doc.text('Notes', col4X, tableTop);

    doc.moveTo(col1X - 10, tableTop + 15).lineTo(540, tableTop + 15).stroke();

    // Rows
    doc.font('Helvetica').fontSize(8);
    let currentY = tableTop + 20;

    assessmentHistory.forEach((assessment) => {
      const date = new Date(assessment.assessment_date).toLocaleDateString();
      const baseline = assessment.is_baseline ? '[Baseline]' : '';

      doc.text(date, col1X, currentY);
      doc.text(assessment.score.toString(), col2X, currentY);
      doc.text(assessment.severity, col3X, currentY);
      doc.text(baseline, col4X, currentY);

      currentY += rowHeight;
    });

    doc.moveDown(2);
  }

  _addTreatmentResponseSection(doc, treatmentResponse) {
    doc.fontSize(14).font('Helvetica-Bold').text('Treatment Response Analysis');
    doc.moveDown(0.3);

    doc.fontSize(10).font('Helvetica');

    const data = [
      ['Baseline PHQ-9 Score', treatmentResponse.baseline_phq9],
      ['Current PHQ-9 Score', treatmentResponse.current_phq9],
      ['Score Improvement', `${treatmentResponse.baseline_phq9 - treatmentResponse.current_phq9} points`],
      ['Response Percentage', `${treatmentResponse.response_percentage}%`],
      ['Treatment Duration', `${treatmentResponse.weeks_since_baseline} weeks`],
      ['Response Status', treatmentResponse.remission_status.replace(/_/g, ' ').toUpperCase()],
    ];

    data.forEach(([label, value]) => {
      doc.text(`${label}: ${value}`);
    });

    doc.moveDown();

    // Clinical Interpretation
    doc.fontSize(9).italics().text(
      'Response defined as ≥25% improvement. Remission defined as ≥50% improvement or score ≤4.',
    );
    doc.moveDown();
  }

  _addRiskFactorsSection(doc, riskFactors) {
    doc.fontSize(14).font('Helvetica-Bold').text('Current Risk Assessment');
    doc.moveDown(0.3);

    doc.fontSize(10).font('Helvetica');
    doc.text(`Risk Level: ${riskFactors.risk_level.toUpperCase()}`);
    doc.text(`Severity Score: ${riskFactors.severity_score}/100`);
    doc.moveDown();

    if (riskFactors.risk_factors) {
      doc.text('Contributing Factors:');
      const factors = typeof riskFactors.risk_factors === 'string' 
        ? JSON.parse(riskFactors.risk_factors) 
        : riskFactors.risk_factors;

      factors.forEach((factor) => {
        doc.fontSize(9).text(`• ${factor}`);
      });
    }

    doc.moveDown();
  }

  _addInterventionsSection(doc, interventions) {
    doc.fontSize(14).font('Helvetica-Bold').text('Current Treatment Plan');
    doc.moveDown(0.3);

    doc.fontSize(9).font('Helvetica');

    interventions.slice(0, 5).forEach((intervention, index) => {
      doc.fontSize(10).font('Helvetica-Bold').text(`${index + 1}. ${intervention.type}`);
      doc.fontSize(9).font('Helvetica');
      doc.text(`Evidence Level: ${intervention.evidence_level}`);

      if (intervention.description) {
        doc.text(intervention.description);
      }

      doc.moveDown(0.3);
    });

    doc.moveDown();
  }

  _addRecommendationsSection(doc, treatmentResponse, riskFactors) {
    doc.fontSize(14).font('Helvetica-Bold').text('Clinical Recommendations');
    doc.moveDown(0.3);

    doc.fontSize(10).font('Helvetica');

    const recommendations = [];

    if (treatmentResponse?.response_percentage < 25) {
      recommendations.push('• Consider treatment adjustment or augmentation strategy');
      recommendations.push('• Evaluate medication compliance and CBT engagement');
    }

    if (riskFactors?.risk_level === 'critical') {
      recommendations.push('• Implement intensive monitoring and crisis protocol');
      recommendations.push('• Consider psychiatric consultation');
    }

    if (recommendations.length === 0) {
      recommendations.push('• Continue current treatment plan as showing positive response');
      recommendations.push('• Maintain regular therapy sessions and medication adherence');
    }

    recommendations.forEach((rec) => {
      doc.text(rec);
    });

    doc.moveDown();
  }

  _addReportFooter(doc) {
    doc.fontSize(8).italics().text(
      'This report is based on standardized clinical assessment tools (PHQ-9) '
      + 'and represents actual collected patient data. '
      + 'All metrics are derived from real behavioral and clinical measurements. '
      + 'Consult with treating clinician for clinical interpretation.',
      { align: 'center' },
    );
  }

  _interpretMood(avgMood) {
    if (avgMood < 3) return 'Severely depressed mood';
    if (avgMood < 5) return 'Significantly low mood';
    if (avgMood < 7) return 'Below average mood';
    if (avgMood < 8) return 'Moderate mood';
    return 'Good mood stability';
  }

  _interpretAnxiety(avgAnxiety) {
    if (avgAnxiety < 3) return 'Low anxiety levels';
    if (avgAnxiety < 5) return 'Mild anxiety';
    if (avgAnxiety < 7) return 'Moderate anxiety';
    if (avgAnxiety < 9) return 'High anxiety';
    return 'Severe anxiety levels';
  }

  _interpretSleep(avgSleep) {
    if (avgSleep < 4) return 'Severe sleep deprivation';
    if (avgSleep < 6) return 'Significant sleep disturbance';
    if (avgSleep < 7) return 'Below recommended sleep';
    if (avgSleep < 9) return 'Healthy sleep duration';
    return 'Excessive sleep (possible depression symptom)';
  }

  _ensureReportsDirectory() {
    if (!fs.existsSync(this.reportsDir)) {
      fs.mkdirSync(this.reportsDir, { recursive: true });
      console.log(`Reports directory created: ${this.reportsDir}`);
    }
  }
}

module.exports = PDFReportService;
