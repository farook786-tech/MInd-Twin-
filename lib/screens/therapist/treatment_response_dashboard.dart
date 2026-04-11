import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/database_service.dart';

class TreatmentResponseDashboard extends StatefulWidget {
  const TreatmentResponseDashboard({super.key});

  @override
  State<TreatmentResponseDashboard> createState() =>
      _TreatmentResponseDashboardState();
}

class _TreatmentResponseDashboardState extends State<TreatmentResponseDashboard> {
  final BackendApiService _backendApiService = BackendApiService();
  final DatabaseService _dbService = DatabaseService();

  List<Map<String, dynamic>> _patients = [];
  Map<String, Map<String, dynamic>> _treatmentData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPatientData();
  }

  Future<void> _loadPatientData() async {
    setState(() => _loading = true);
    try {
      final patients = await _dbService.getAllPatients();
      final treatmentMap = <String, Map<String, dynamic>>{};

      for (final patient in patients) {
        final summary = await _backendApiService.getTreatmentSummary(patient.id);
        treatmentMap[patient.id] = summary;
      }

      if (!mounted) return;
      setState(() {
        _patients = patients
            .map((p) => {'id': p.id, 'name': p.name, 'email': p.email})
            .cast<Map<String, dynamic>>()
            .toList();
        _treatmentData = treatmentMap;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.trending_up_rounded,
                  color: AppTheme.primaryIndigo, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Treatment Response Dashboard',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadPatientData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPatientData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildOverview(),
                  const SizedBox(height: 24),
                  _buildPatientsList(),
                ],
              ),
            ),
    );
  }

  Widget _buildOverview() {
    int patientsInRemission = 0;
    double avgResponseRate = 0;

    for (final data in _treatmentData.values) {
      if (data['treatmentResponse'] != null) {
        if (data['treatmentResponse']['remissionStatus'] == 'remission') {
          patientsInRemission++;
        }
        avgResponseRate += (data['treatmentResponse']['responsePercentage'] ?? 0) /
            (_treatmentData.isNotEmpty ? _treatmentData.length : 1);
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cohort Performance Summary',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Patients Tracked',
                  _treatmentData.length.toString(),
                  Colors.blue,
                  Icons.people_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'In Remission',
                  patientsInRemission.toString(),
                  Colors.green,
                  Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Avg Response',
                  '${avgResponseRate.toStringAsFixed(0)}%',
                  const Color(0xFFFFA726),
                  Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientsList() {
    if (_patients.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No patients assigned yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Patient Treatment Progress',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_patients.length, (index) {
          final patient = _patients[index];
          final patientId = patient['id'] as String;
          final treatment = _treatmentData[patientId] ?? {};

          return _buildPatientCard(patient, treatment);
        }),
      ],
    );
  }

  Widget _buildPatientCard(
    Map<String, dynamic> patient,
    Map<String, dynamic> treatment,
  ) {
    final baseline = treatment['baseline'] as Map<String, dynamic>?;
    final current = treatment['current'] as Map<String, dynamic>?;
    final response = treatment['treatmentResponse'] as Map<String, dynamic>?;

    final baselineScore = baseline?['score'] as int?;
    final currentScore = current?['score'] as int?;
    final responsePercentage = response?['responsePercentage'] as int? ?? 0;
    final remissionStatus = response?['remissionStatus'] as String? ?? 'no_data';
    final weeksSince = response?['weeksSinceBa seline'] as int? ?? 0;

    Color statusColor;
    if (remissionStatus == 'remission') {
      statusColor = AppTheme.safeGreen;
    } else if (remissionStatus == 'significant_progress') {
      statusColor = const Color(0xFFFFA726);
    } else {
      statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient['name'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      patient['email'] as String,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Text(
                  remissionStatus.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // PHQ-9 Score Progression
          if (baselineScore != null && currentScore != null) ...[
            Row(
              children: [
                Expanded(
                  child: _buildScoreColumn('Baseline', baselineScore.toString()),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white30,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildScoreColumn('Current', currentScore.toString()),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildScoreColumn(
                    'Change',
                    (baselineScore - currentScore).toString(),
                    (baselineScore - currentScore) > 0
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Response Rate Progress Bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Response Rate',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$responsePercentage%',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: responsePercentage / 100,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (weeksSince > 0)
              Text(
                'Tracked for $weeksSince weeks',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Awaiting baseline assessment or follow-up',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreColumn(String label, String score, [Color? color]) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (color ?? Colors.white.withValues(alpha: 0.2)),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            score,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
