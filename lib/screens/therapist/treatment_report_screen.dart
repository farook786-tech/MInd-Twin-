import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/auth_service.dart';

class TreatmentReportScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const TreatmentReportScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<TreatmentReportScreen> createState() => _TreatmentReportScreenState();
}

class _TreatmentReportScreenState extends State<TreatmentReportScreen> {
  final BackendApiService _backendApiService = BackendApiService();
  final AuthService _authService = AuthService();

  String? _therapistId;
  bool _generatingTreatment = false;
  bool _generatingProgress = false;
  bool _generatingWearable = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _therapistId = _authService.currentUserId ?? 'therapist_main';
      setState(() {});
    } catch (e) {
      debugPrint('Failed to resolve therapist id: $e');
    }
  }

  Future<void> _generateTreatmentReport() async {
    if (_therapistId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Therapist ID not found')),
      );
      return;
    }

    setState(() => _generatingTreatment = true);

    try {
      final fileName = await _backendApiService.downloadTreatmentReport(
        widget.patientId,
        _therapistId!,
      );

      if (!mounted) return;

      if (fileName != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ Report downloaded: $fileName')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate report')),
        );
      }

      setState(() => _generatingTreatment = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _generatingTreatment = false);
    }
  }

  Future<void> _generateProgressReport() async {
    setState(() => _generatingProgress = true);

    try {
      final fileName = await _backendApiService.downloadProgressReport(widget.patientId);

      if (!mounted) return;

      if (fileName != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ Report downloaded: $fileName')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate report')),
        );
      }

      setState(() => _generatingProgress = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _generatingProgress = false);
    }
  }

  Future<void> _generateWearableReport() async {
    setState(() => _generatingWearable = true);

    try {
      final fileName = await _backendApiService.downloadWearableReport(widget.patientId, days: 30);

      if (!mounted) return;

      if (fileName != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ Report downloaded: $fileName')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate report')),
        );
      }

      setState(() => _generatingWearable = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _generatingWearable = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.description_rounded,
                      color: Colors.red, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Treatment Reports',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.patientName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReportInfo(),
            const SizedBox(height: 24),
            _buildTreatmentReportCard(),
            const SizedBox(height: 12),
            _buildProgressReportCard(),
            const SizedBox(height: 12),
            _buildWearableReportCard(),
            const SizedBox(height: 24),
            _buildReportTips(),
          ],
        ),
      ),
    );
  }

  Widget _buildReportInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clinical Report Suite',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Generate hospital-grade PDF reports for clinical documentation. '
            'All reports are based on real collected patient data.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreatmentReportCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Comprehensive Treatment Report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Full clinical analysis with PHQ-9 trajectory',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Includes:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildReportItem('Executive Summary'),
                _buildReportItem('PHQ-9 Score Trajectory'),
                _buildReportItem('Treatment Response Analysis'),
                _buildReportItem('Risk Factor Assessment'),
                _buildReportItem('Current Treatment Plan'),
                _buildReportItem('Clinical Recommendations'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generatingTreatment ? null : _generateTreatmentReport,
              icon: _generatingTreatment
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_generatingTreatment ? 'Generating...' : 'Generate Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressReportCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Progress Report (Quick View)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Simple summary of recent assessments',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Includes:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildReportItem('Patient Information'),
                _buildReportItem('Recent PHQ-9 Assessment History'),
                _buildReportItem('Baseline and Current Scores'),
                _buildReportItem('Treatment Duration'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generatingProgress ? null : _generateProgressReport,
              icon: _generatingProgress
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_generatingProgress ? 'Generating...' : 'Generate Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWearableReportCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Wearable Data Summary',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Real-time health metrics from last 30 days',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Includes:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildReportItem('Mood Trends'),
                _buildReportItem('Anxiety Level Tracking'),
                _buildReportItem('Sleep Quality Analysis'),
                _buildReportItem('Heart Rate Monitoring'),
                _buildReportItem('Activity & Steps'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generatingWearable ? null : _generateWearableReport,
              icon: _generatingWearable
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_generatingWearable ? 'Generating...' : 'Generate Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportItem(String item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_rounded, size: 12, color: Colors.green),
          const SizedBox(width: 6),
          Text(
            item,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTips() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_rounded, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Text(
                'About Clinical Reports',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• All reports are hospital-grade clinical documents\n'
            '• Based on real collected patient data (PHQ-9, wearables, behavioral data)\n'
            '• Use for clinical documentation and treatment planning\n'
            '• Update regularly to track treatment progress\n'
            '• Include evidence-based recommendations',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
