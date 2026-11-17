import 'package:mindtwin/widgets/clinical_status_card.dart';
import 'package:mindtwin/widgets/patient_vitals_panel.dart';
import 'package:mindtwin/widgets/twin_drift_card.dart';
import '../../services/digital_twin_service.dart' show DriftResult;
import 'package:mindtwin/widgets/session_brief_sheet.dart';
import '../../services/clinical_scoring.dart' show EarlyWarning;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../models/patient.dart';
import '../../services/auth_service.dart';
import '../../services/ml_analysis_service.dart' show MLAnalysisService, MentalHealthAnalysis;
import 'appointments_screen.dart';
import 'session_notes_screen.dart';
import 'treatment_plan_screen.dart';
import 'therapist_ai_chat_screen.dart';
import '../chat/chat_screen.dart';
import '../patient/safety_plan_screen.dart';
import '../../services/daily_log_source.dart';

/// Therapist view of ONE patient. Everything here is live Firestore data
/// (docs/DATA_MODEL.md), never the therapist's local SQLite:
/// * `users/{patientId}` snapshot: risk, wellbeing, last check-in, PHQ-9,
///   vital thresholds (the only field the therapist may write).
/// * `daily_logs` where patientId == X && therapistId == me, newest first.
/// * `journal_entries` where patientId == X && therapistId == me, newest first.
/// * `PatientVitalsPanel` (wearable vitals) at the top.
class PatientDetailsScreen extends StatefulWidget {
  final Patient patient;

  const PatientDetailsScreen({super.key, required this.patient});

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  static const double _defaultHrHigh = 120;
  static const double _defaultHrLow = 45;
  static const double _defaultSleepLow = 4;

  final MLAnalysisService _mlService = MLAnalysisService();
  final AuthService _authService = AuthService();

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _logsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _journalStream;

  MentalHealthAnalysis? _analysis;
  bool _analysisLoading = false;

  /// Latest Digital Twin drift (personal-baseline early warning). Shown in its own card
  /// and listed under the Clinical status card's early warnings; never changes the level.
  DriftResult? _drift;

  /// Latest patient model built from the live users doc (used for navigation
  /// to tools that take a [Patient]).
  late Patient _current;
  Map<String, dynamic> _userData = const {};

  @override
  void initState() {
    super.initState();
    _current = widget.patient;
    final firestore = FirebaseFirestore.instance;
    _userStream = firestore.collection('users').doc(widget.patient.id).snapshots();
    _logsStream = DailyLogSource.scopedQuery(widget.patient.id).limit(30).snapshots();
    final therapistId = _authService.currentUserId;
    if (therapistId != null) {
      _journalStream = firestore
          .collection('journal_entries')
          .where('patientId', isEqualTo: widget.patient.id)
          .where('therapistId', isEqualTo: therapistId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();
    }
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    setState(() => _analysisLoading = true);
    try {
      // Reads Firestore daily_logs through DailyLogSource (therapist-scoped).
      final logs = await DailyLogSource().getDailyLogs(widget.patient.id, limit: 30);
      MentalHealthAnalysis? analysis;
      if (logs.length >= 3) {
        analysis = await _mlService.analyzePatientHealth(widget.patient.id);
      }
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _analysisLoading = false;
      });
    } catch (e) {
      debugPrint('Patient ML analysis failed: $e');
      if (!mounted) return;
      setState(() => _analysisLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, userSnap) {
        final data = userSnap.data?.data();
        if (data != null) {
          _userData = data;
          _current = Patient.fromFirestore(widget.patient.id, data, fallbackName: widget.patient.name);
        }
        final patient = _current;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.cardDark,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient.name.isEmpty ? 'Patient' : patient.name),
                if (patient.email.isNotEmpty || patient.age > 0)
                  Text(
                    [
                      if (patient.age > 0) '${patient.age} years',
                      if (patient.email.isNotEmpty) patient.email,
                    ].join(' • '),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.summarize_outlined),
                tooltip: 'Pre-session brief',
                onPressed: () => showSessionBriefSheet(context, patientId: widget.patient.id),
              ),
              IconButton(
                icon: const Icon(Icons.assignment_turned_in_outlined),
                tooltip: 'Safety plan',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SafetyPlanScreen(
                      patientId: patient.id,
                      patientName: patient.name,
                      asTherapist: true,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.smart_toy),
                tooltip: 'AI Clinical Assistant',
                onPressed: () {
                  final therapistId = _authService.currentUserId;
                  if (therapistId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please sign in again.')),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TherapistAIChatScreen(
                        therapistId: therapistId,
                        patientId: patient.id,
                        patientName: patient.name,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.chat),
                tooltip: 'Message patient',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        otherUserId: patient.id,
                        otherUserName: patient.name,
                        isTherapist: true,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: _buildBody(userSnap),
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> userSnap) {
    if (userSnap.hasError) {
      return _ErrorPanel(
        message: _firestoreErrorText(
          userSnap.error,
          permissionText: 'You do not have access to this patient. They may be linked to another therapist.',
        ),
      );
    }
    if (!userSnap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!userSnap.data!.exists) {
      return const _ErrorPanel(message: 'This patient account no longer exists.');
    }

    return RefreshIndicator(
      onRefresh: _loadAnalysis,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Validated-instrument clinical status (PHQ-9 / GAD-7 / C-SSRS)
            // with early-warning signals listed separately.
            ClinicalStatusCard(
              patientId: widget.patient.id,
              extraEarlyWarnings: [
                if (_analysis != null && _analysis!.anomalyDetected)
                  EarlyWarning(
                    source: 'Check-in pattern change (statistical)',
                    detail: _analysis!.anomalyDescription,
                    flagged: true,
                  ),
                if (_drift?.toEarlyWarning() case final drift?) drift,
              ],
            ),
            const SizedBox(height: 16),
            // Digital Twin drift: recent days vs the patient's own 28-day baseline.
            TwinDriftCard(
              patientId: widget.patient.id,
              therapistView: true,
              onResult: (r) {
                if (mounted) setState(() => _drift = r);
              },
            ),
            const SizedBox(height: 16),
            // Live wearable vitals (owned by the vitals engineer).
            PatientVitalsPanel(patientId: widget.patient.id),
            const SizedBox(height: 16),
            _buildThresholdsCard(),
            const SizedBox(height: 16),
            _buildRiskCard(),
            const SizedBox(height: 16),
            if (_analysisLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(),
              ),
            if (_analysis != null) ...[
              _buildMLAnalysisCard(),
              const SizedBox(height: 16),
            ],
            _buildActionGrid(),
            const SizedBox(height: 16),
            _buildActivityTimeline(),
            const SizedBox(height: 16),
            _buildJournalSection(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Vital thresholds (users/{patientId}.vitalThresholds — the ONLY field of the
  // patient's user doc a therapist may write).
  // ---------------------------------------------------------------------------

  ({double hrHigh, double hrLow, double sleepLow, bool isDefault}) _thresholds() {
    final t = _userData['vitalThresholds'];
    double pick(String key, double fallback) {
      if (t is Map && t[key] is num) return (t[key] as num).toDouble();
      return fallback;
    }

    return (
      hrHigh: pick('heartRateHigh', _defaultHrHigh),
      hrLow: pick('heartRateLow', _defaultHrLow),
      sleepLow: pick('sleepHoursLow', _defaultSleepLow),
      isDefault: t is! Map,
    );
  }

  Widget _buildThresholdsCard() {
    final t = _thresholds();
    String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return Card(
      color: AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.tune_rounded, color: Colors.pinkAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.isDefault ? 'Vital alert thresholds (defaults)' : 'Vital alert thresholds',
                    style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Heart rate: alert below ${fmt(t.hrLow)} or above ${fmt(t.hrHigh)} bpm\n'
                    'Sleep: alert below ${fmt(t.sleepLow)} h',
                    style: TextStyle(color: AppColors.ink.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _editThresholds,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editThresholds() async {
    final t = _thresholds();
    final result = await showDialog<Map<String, num>>(
      context: context,
      builder: (_) => _ThresholdsDialog(hrHigh: t.hrHigh, hrLow: t.hrLow, sleepLow: t.sleepLow),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // update() of exactly one field; rules reject anything else.
      await FirebaseFirestore.instance.collection('users').doc(widget.patient.id).update({
        'vitalThresholds': result,
      });
      messenger.showSnackBar(const SnackBar(content: Text('Vital thresholds saved.')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.riskRed,
          content: Text('Thresholds NOT saved: ${_firestoreErrorText(error)}'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Risk overview (users.latestRiskScore 0-100, latestWellbeingScore,
  // lastCheckInAt, latestPhq9).
  // ---------------------------------------------------------------------------

  Widget _buildRiskCard() {
    final risk = _current.latestRiskScore; // 0..100 or null
    final wellbeing = _current.latestWellbeingScore;
    final lastCheckIn = _current.lastCheckInAt;
    final Color riskColor;
    final String riskLabel;
    // Self-report heuristic from the daily check-in (mood/sleep/energy/worries).
    // An early-warning signal, NOT a risk prediction or diagnosis; the
    // clinical level comes from the Clinical status card above.
    if (risk == null) {
      riskColor = AppColors.ink54;
      riskLabel = 'NO DATA';
    } else if (risk >= 75) {
      riskColor = AppTheme.riskRed;
      riskLabel = 'VERY HIGH STRAIN';
    } else if (risk >= 50) {
      riskColor = AppTheme.riskRed;
      riskLabel = 'HIGH STRAIN';
    } else if (risk >= 25) {
      riskColor = AppTheme.warningAmber;
      riskLabel = 'SOME STRAIN';
    } else {
      riskColor = AppTheme.safeGreen;
      riskLabel = 'LITTLE STRAIN';
    }

    final phq = _userData['latestPhq9'];
    final phqTotal = phq is Map ? phq['total'] : _userData['latestPhq9Score'];
    final phqSeverity = phq is Map ? phq['severity']?.toString() : null;
    final phqAt = phq is Map ? _toDate(phq['at']) : _toDate(_userData['latestAssessmentAt']);

    return Card(
      color: AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Check-in wellbeing indicator',
                    style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: riskColor, width: 2),
                  ),
                  child: Text(
                    riskLabel,
                    style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              width: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 100,
                    width: 100,
                    child: CircularProgressIndicator(
                      value: risk == null ? 0 : risk / 100,
                      strokeWidth: 12,
                      backgroundColor: AppColors.ink.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(riskColor),
                    ),
                  ),
                  Text(
                    risk == null ? '—' : '${risk.round()}',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              risk == null
                  ? 'Check-in wellbeing indicator: — (no check-in yet)'
                  : 'Check-in wellbeing indicator ${risk.round()}/100 (higher = more strain reported)',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.75), fontSize: 13),
            ),
            Text(
              'Self-report heuristic; early-warning only, not diagnostic.',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.5), fontSize: 11),
            ),
            if (wellbeing != null)
              Text(
                'Wellbeing ${wellbeing.round()}/100',
                style: TextStyle(color: AppColors.ink.withValues(alpha: 0.75), fontSize: 13),
              ),
            if (phqTotal is num)
              Text(
                'Latest PHQ-9: ${phqTotal.round()}/27'
                '${phqSeverity == null ? '' : ' ($phqSeverity)'}'
                '${phqAt == null ? '' : ' • ${_formatDate(phqAt)}'}',
                style: TextStyle(
                  color: phqTotal >= 20 ? AppTheme.riskRed : AppColors.ink.withValues(alpha: 0.75),
                  fontSize: 13,
                ),
              ),
            const SizedBox(height: 6),
            Text(
              lastCheckIn == null ? 'Last check-in: never' : 'Last check-in: ${_formatDate(lastCheckIn)}',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMLAnalysisCard() {
    final analysis = _analysis!;
    
    return Card(
      color: AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: AppTheme.primaryIndigo, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Check-in trend (early warning, not diagnostic)',
                    style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildAnalysisRow('Check-in trend', analysis.trendDirection, _getTrendIcon(analysis.trendDirection)),
            _buildAnalysisRow(
              'Check-ins analysed',
              '${analysis.detailedMetrics['dataPoints'] ?? '—'}',
              Icons.event_note_rounded,
            ),
            if (analysis.anomalyDetected)
              _buildAnalysisRow('Pattern change', 'Detected', Icons.warning, color: AppTheme.warningAmber),
            if (analysis.anomalyDetected && analysis.anomalyDescription.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 8),
                child: Text(
                  analysis.anomalyDescription,
                  style: TextStyle(color: AppColors.ink70, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Statistical summary of the patient\'s self-reported check-ins (moving averages and '
              'slope). It is not a prediction of clinical outcome, a diagnosis, or a treatment '
              'recommendation.',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.5), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisRow(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppColors.ink.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text('$label:', style: TextStyle(color: AppColors.ink70, fontSize: 13)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(color: color ?? AppColors.ink, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  IconData _getTrendIcon(String trend) {
    if (trend.toLowerCase().contains('improving')) return Icons.trending_down;
    if (trend.toLowerCase().contains('declining')) return Icons.trending_up;
    return Icons.trending_flat;
  }

  Widget _buildActionGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Clinical Tools',
          style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildActionCard(
              'Session Notes',
              Icons.note_alt,
              AppTheme.primaryIndigo,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionNotesScreen(patient: _current),
                  ),
                );
              },
            ),
            _buildActionCard(
              'Treatment Plan',
              Icons.assignment,
              Colors.teal,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TreatmentPlanScreen(patient: _current),
                  ),
                );
              },
            ),
            _buildActionCard(
              'Appointments',
              Icons.calendar_today,
              Colors.orange,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppointmentsScreen(
                      patientId: widget.patient.id,
                      patientName: widget.patient.name,
                    ),
                  ),
                );
              },
            ),
            _buildActionCard(
              'Export Report',
              Icons.picture_as_pdf,
              AppTheme.riskRed,
              _exportPatientReport,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      color: AppTheme.cardDark,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Check-in History',
          style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _logsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(message: _firestoreErrorText(snapshot.error));
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return _mutedCard('No check-in history yet');
            }
            return Card(
              color: AppTheme.cardDark,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: docs.map((d) => _buildTimelineItem(d.data())).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// One daily_logs doc. `moodScore` is the check-in choice on an inverted
  /// 1..5 scale (1 = great .. 5 = worst); shown as 0..10 where 10 = best,
  /// matching the dashboard mood chart. `riskScore` is 0..100.
  Widget _buildTimelineItem(Map<String, dynamic> log) {
    final risk = (log['riskScore'] is num) ? (log['riskScore'] as num).toDouble() : null;
    final moodScore = (log['moodScore'] is num) ? (log['moodScore'] as num).toDouble() : null;
    final mood10 = moodScore == null ? null : ((5 - moodScore.clamp(1.0, 5.0)) / 4) * 10;
    final color = risk == null
        ? AppColors.ink54
        : risk >= 75
            ? AppTheme.riskRed
            : risk >= 50
                ? const Color(0xFFE37A42)
                : risk >= 25
                    ? AppTheme.warningAmber
                    : AppTheme.safeGreen;
    final when = _toDate(log['timestamp']);
    final note = (log['optionalNote'] ?? '').toString().trim();
    final details = <String>[
      if (log['mood'] != null) 'Mood: ${log['mood']}${mood10 == null ? '' : ' (${mood10.toStringAsFixed(1)}/10)'}',
      if (log['sleep'] != null) 'Sleep: ${log['sleep']}',
      if (log['energy'] != null) 'Energy: ${log['energy']}',
      'Check-in indicator: ${risk == null ? '—' : '${risk.round()}/100'}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  when == null ? 'Pending sync' : DateFormat('MMM dd, yyyy • HH:mm').format(when.toLocal()),
                  style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  details.isEmpty ? 'No details recorded' : details.join(' • '),
                  style: TextStyle(color: AppColors.ink.withValues(alpha: 0.7), fontSize: 12),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '"$note"',
                    style: TextStyle(
                      color: AppColors.ink.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Voice / text journal entries written by the patient app.
  // ---------------------------------------------------------------------------

  Widget _buildJournalSection() {
    final stream = _journalStream;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Journal Entries',
          style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (stream == null)
          _mutedCard('Sign in again to view journal entries.')
        else
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorPanel(message: _firestoreErrorText(snapshot.error));
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return _mutedCard('No journal entries shared yet');
              }
              return Column(
                children: docs.map((d) => _buildJournalItem(d.data())).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildJournalItem(Map<String, dynamic> entry) {
    final when = _toDate(entry['createdAt']) ?? _toDate(entry['clientCreatedAt']);
    final text = (entry['transcript'] ?? entry['text'] ?? '').toString().trim();
    final mood = entry['mood']?.toString();
    final duration = entry['durationSeconds'];
    final meta = <String>[
      when == null ? 'Pending sync' : DateFormat('MMM dd, yyyy • HH:mm').format(when.toLocal()),
      if (mood != null && mood.isNotEmpty) 'Mood: $mood',
      if (duration is num && duration > 0) '${duration.round()} s recording',
    ];
    return Card(
      color: AppTheme.cardDark,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mic_rounded, color: AppTheme.primaryIndigo, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    meta.join(' • '),
                    style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6), fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text.isEmpty ? '(no transcript)' : text,
              style: TextStyle(color: AppColors.ink, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mutedCard(String text) {
    return Card(
      color: AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(text, style: TextStyle(color: AppColors.ink.withValues(alpha: 0.5))),
        ),
      ),
    );
  }

  void _exportPatientReport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: Row(
          children: [
            Icon(Icons.picture_as_pdf, color: AppTheme.riskRed),
            SizedBox(width: 8),
            Text('Export Patient Report', style: TextStyle(color: AppColors.ink)),
          ],
        ),
        content: Text(
          'Generate a comprehensive PDF report including:\n\n'
          '• Patient demographics\n'
          '• Validated assessment history (PHQ-9, GAD-7, C-SSRS)\n'
          '• Treatment plan (clinician-authored)\n'
          '• Session notes\n'
          '• Early-warning signals (not diagnostic)\n'
          '• Check-in timeline\n\n'
          'This feature requires pdf package integration.',
          style: TextStyle(color: AppColors.ink70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📄 PDF export feature will be available after adding pdf package'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.riskRed),
            icon: const Icon(Icons.download),
            label: const Text('Generate PDF'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today ${DateFormat('HH:mm').format(date.toLocal())}';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('MMM dd, yyyy').format(date.toLocal());
  }
}

DateTime? _toDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _firestoreErrorText(Object? error, {String? permissionText}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return permissionText ??
            'Permission denied. Confirm your therapist account is approved and this patient is linked to you.';
      case 'failed-precondition':
        return 'A required database index is missing or still building. Data will appear once it is ready.';
      case 'unavailable':
        return 'Network unavailable. Retrying automatically.';
    }
    return error.message ?? error.code;
  }
  return error?.toString() ?? 'Unknown error';
}

class _ErrorPanel extends StatelessWidget {
  final String message;

  const _ErrorPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.riskRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.riskRed.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppTheme.riskRed),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: AppColors.ink))),
        ],
      ),
    );
  }
}

/// Edits heart-rate high/low (bpm) and sleep-low (hours) thresholds with
/// clinical sanity bounds. Returns the new `vitalThresholds` map.
class _ThresholdsDialog extends StatefulWidget {
  final double hrHigh;
  final double hrLow;
  final double sleepLow;

  const _ThresholdsDialog({required this.hrHigh, required this.hrLow, required this.sleepLow});

  @override
  State<_ThresholdsDialog> createState() => _ThresholdsDialogState();
}

class _ThresholdsDialogState extends State<_ThresholdsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hrHigh;
  late final TextEditingController _hrLow;
  late final TextEditingController _sleepLow;

  @override
  void initState() {
    super.initState();
    String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    _hrHigh = TextEditingController(text: fmt(widget.hrHigh));
    _hrLow = TextEditingController(text: fmt(widget.hrLow));
    _sleepLow = TextEditingController(text: fmt(widget.sleepLow));
  }

  @override
  void dispose() {
    _hrHigh.dispose();
    _hrLow.dispose();
    _sleepLow.dispose();
    super.dispose();
  }

  String? _range(String? raw, double min, double max, String unit) {
    final v = double.tryParse((raw ?? '').trim());
    if (v == null) return 'Enter a number';
    if (v < min || v > max) return 'Must be $min-$max $unit';
    return null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final hrHigh = double.parse(_hrHigh.text.trim()).round();
    final hrLow = double.parse(_hrLow.text.trim()).round();
    final sleepLow = double.parse(double.parse(_sleepLow.text.trim()).toStringAsFixed(1));
    Navigator.pop<Map<String, num>>(context, {
      'heartRateHigh': hrHigh,
      'heartRateLow': hrLow,
      'sleepHoursLow': sleepLow,
    });
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppColors.ink70),
        );
    return AlertDialog(
      backgroundColor: AppTheme.cardDark,
      title: Text('Vital alert thresholds', style: TextStyle(color: AppColors.ink)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _hrHigh,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                style: TextStyle(color: AppColors.ink),
                decoration: deco('Heart rate HIGH (bpm)'),
                validator: (v) {
                  final err = _range(v, 80, 220, 'bpm');
                  if (err != null) return err;
                  final low = double.tryParse(_hrLow.text.trim());
                  if (low != null && double.parse(v!.trim()) - low < 20) {
                    return 'Must be at least 20 bpm above the low threshold';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _hrLow,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                style: TextStyle(color: AppColors.ink),
                decoration: deco('Heart rate LOW (bpm)'),
                validator: (v) => _range(v, 25, 90, 'bpm'),
              ),
              TextFormField(
                controller: _sleepLow,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: AppColors.ink),
                decoration: deco('Sleep LOW (hours per night)'),
                validator: (v) => _range(v, 0, 12, 'h'),
              ),
              const SizedBox(height: 12),
              Text(
                'Out-of-range readings create a crisis alert (30 min cooldown per vital).',
                style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _hrHigh.text = '120';
            _hrLow.text = '45';
            _sleepLow.text = '4';
          },
          child: const Text('Reset to defaults'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
