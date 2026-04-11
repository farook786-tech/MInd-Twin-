import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../models/patient.dart';
import '../../models/daily_log.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../services/ml_analysis_service.dart' show MLAnalysisService, MentalHealthAnalysis;
import 'session_notes_screen.dart';
import 'treatment_plan_screen.dart';
import 'therapist_ai_chat_screen.dart';
import '../chat/chat_screen.dart';

class PatientDetailsScreen extends StatefulWidget {
  final Patient patient;

  const PatientDetailsScreen({super.key, required this.patient});

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final MLAnalysisService _mlService = MLAnalysisService();
  final AuthService _authService = AuthService();
  List<DailyLog> _logs = [];
  MentalHealthAnalysis? _analysis;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _dbService.getDailyLogs(widget.patient.id);
      late MentalHealthAnalysis? analysis;
      
      if (logs.length >= 3) {
        analysis = await _mlService.analyzePatientHealth(widget.patient.id);
      }
      
      setState(() {
        _logs = logs;
        _analysis = analysis;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading patient data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.patient.name),
            Text(
              '${widget.patient.age} years • ${widget.patient.email}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy),
            tooltip: 'AI Clinical Assistant',
            onPressed: () {
              final therapistId = _authService.currentUserId ?? 'therapist_demo';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TherapistAIChatScreen(
                    therapistId: therapistId,
                    patientId: widget.patient.id,
                    patientName: widget.patient.name,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    otherUserId: widget.patient.id,
                    otherUserName: widget.patient.name,
                    isTherapist: true,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Risk overview card
                  _buildRiskCard(),
                  const SizedBox(height: 16),
                  
                  // ML Analysis card
                  if (_analysis != null) ...[
                    _buildMLAnalysisCard(),
                    const SizedBox(height: 16),
                  ],
                  
                  // Action buttons grid
                  _buildActionGrid(),
                  const SizedBox(height: 16),
                  
                  // Recent activity timeline
                  _buildActivityTimeline(),
                ],
              ),
            ),
    );
  }

  Widget _buildRiskCard() {
    final riskScore = widget.patient.riskScore;
    final riskColor = riskScore > 0.6
        ? AppTheme.riskRed
        : riskScore > 0.3
            ? AppTheme.warningAmber
            : AppTheme.safeGreen;
    final riskLabel = riskScore > 0.6
        ? 'HIGH RISK'
        : riskScore > 0.3
            ? 'MODERATE'
            : 'LOW RISK';

    return Card(
      color: AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current Risk Level',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                      value: riskScore,
                      strokeWidth: 12,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(riskColor),
                    ),
                  ),
                  Text(
                    '${(riskScore * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Last check-in: ${_formatDate(widget.patient.lastCheckIn)}',  
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
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
            const Row(
              children: [
                Icon(Icons.psychology, color: AppTheme.primaryIndigo, size: 20),
                SizedBox(width: 8),
                Text(
                  'AI Analysis',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildAnalysisRow('Trend', analysis.trendDirection, _getTrendIcon(analysis.trendDirection)),
            _buildAnalysisRow('Prediction (7d)', '${(analysis.prediction.isNotEmpty ? analysis.prediction[6] * 100 : 0).toInt()}%', Icons.trending_up),
            if (analysis.anomalyDetected) 
              _buildAnalysisRow('Anomalies', 'Detected', Icons.warning, color: AppTheme.warningAmber),
            const SizedBox(height: 12),
            if (analysis.recommendation.isNotEmpty) ...[  
              const Text('Recommendation:', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Text('• ', style: TextStyle(color: AppTheme.primaryIndigo)),
                    Expanded(child: Text(analysis.recommendation, style: const TextStyle(color: Colors.white, fontSize: 13))),
                  ],
                ),
              ),
            ],
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
          Icon(icon, size: 16, color: color ?? Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text('$label:', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
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
        const Text(
          'Clinical Tools',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                    builder: (_) => SessionNotesScreen(patient: widget.patient),
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
                    builder: (_) => TreatmentPlanScreen(patient: widget.patient),
                  ),
                );
              },
            ),
            _buildActionCard(
              'Appointments',
              Icons.calendar_today,
              Colors.orange,
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Opens appointment scheduler for this patient')),
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
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityTimeline() {
    if (_logs.isEmpty) {
      return Card(
        color: AppTheme.cardDark,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No check-in history yet',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Check-in History',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppTheme.cardDark,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _logs.take(10).map((log) => _buildTimelineItem(log)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(DailyLog log) {
    final avgScore = (log.moodScore + (10 - log.anxietyLevel) + (log.sleepHours / 8 * 10)) / 3;
    final color = avgScore >= 7 ? AppTheme.safeGreen : avgScore >= 5 ? AppTheme.warningAmber : AppTheme.riskRed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMM dd, yyyy').format(log.timestamp),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mood: ${log.moodScore}/10 • Anxiety: ${log.anxietyLevel}/10 • Sleep: ${log.sleepHours}h',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _exportPatientReport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: AppTheme.riskRed),
            SizedBox(width: 8),
            Text('Export Patient Report', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Generate a comprehensive PDF report including:\n\n'
          '• Patient demographics\n'
          '• Risk assessment history\n'
          '• Treatment plan\n'
          '• Session notes\n'
          '• ML analysis\n'
          '• Check-in timeline\n\n'
          'This feature requires pdf package integration.',
          style: TextStyle(color: Colors.white70),
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

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('MMM dd, yyyy').format(date);
  }
}
