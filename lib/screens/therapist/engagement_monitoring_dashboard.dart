import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/database_service.dart';

class EngagementMonitoringDashboard extends StatefulWidget {
  const EngagementMonitoringDashboard({super.key});

  @override
  State<EngagementMonitoringDashboard> createState() =>
      _EngagementMonitoringDashboardState();
}

class _EngagementMonitoringDashboardState
    extends State<EngagementMonitoringDashboard> {
  final BackendApiService _backendApiService = BackendApiService();
  final DatabaseService _dbService = DatabaseService();

  List<Map<String, dynamic>> _patients = [];
  Map<String, Map<String, dynamic>> _engagementData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEngagementData();
  }

  Future<void> _loadEngagementData() async {
    setState(() => _loading = true);
    try {
      final patients = await _dbService.getAllPatients();
      final engagementMap = <String, Map<String, dynamic>>{};

      for (final patient in patients) {
        final engagement = await _backendApiService.getEngagementMetrics(patient.id);
        engagementMap[patient.id] = engagement;
      }

      if (!mounted) return;
      setState(() {
        _patients = patients
            .map((p) => {'id': p.id, 'name': p.name, 'email': p.email})
            .cast<Map<String, dynamic>>()
            .toList();
        _engagementData = engagementMap;
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
              child: const Icon(Icons.people_outline_rounded,
                  color: AppTheme.primaryIndigo, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Engagement Monitoring',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadEngagementData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEngagementData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildRiskDistribution(),
                  const SizedBox(height: 24),
                  _buildPatientsList(),
                ],
              ),
            ),
    );
  }

  Widget _buildRiskDistribution() {
    final critical =
        _engagementData.values.where((e) => (e['dropoutRisk'] ?? 0) >= 70).length;
    final high =
        _engagementData.values.where((e) => (e['dropoutRisk'] ?? 0) >= 50 && (e['dropoutRisk'] ?? 0) < 70).length;
    final medium = _engagementData.values
        .where((e) => (e['dropoutRisk'] ?? 0) >= 30 && (e['dropoutRisk'] ?? 0) < 50)
        .length;
    final low = _engagementData.values
        .where((e) => (e['dropoutRisk'] ?? 0) < 30)
        .length;

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
            'Risk Distribution',
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
                child: _buildRiskCard('Critical', critical, Colors.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRiskCard('High', high, Colors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRiskCard('Medium', medium, const Color(0xFFFFA726)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRiskCard('Low', low, Colors.green),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Risk spectrum bar
          Container(
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [
                  Colors.green,
                  Color(0xFFFFA726),
                  Colors.orange,
                  Colors.red,
                ],
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Low (0)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  Text('Medium (30)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  Text('High (50)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  Text('Critical (70)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskCard(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.people_rounded, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            count.toString(),
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

    // Sort by dropout risk (highest first)
    final sortedPatients = _patients.toList();
    sortedPatients.sort((a, b) {
      final riskA = (_engagementData[a['id']]?['dropoutRisk'] as int?) ?? 0;
      final riskB = (_engagementData[b['id']]?['dropoutRisk'] as int?) ?? 0;
      return riskB.compareTo(riskA);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Patient Engagement Status',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(sortedPatients.length, (index) {
          final patient = sortedPatients[index];
          final engagementMetrics =
              _engagementData[patient['id']] ?? {};

          return _buildPatientCard(patient, engagementMetrics);
        }),
      ],
    );
  }

  Widget _buildPatientCard(
    Map<String, dynamic> patient,
    Map<String, dynamic> engagementMetrics,
  ) {
    final dropoutRisk = (engagementMetrics['dropoutRisk'] as int?) ?? 0;
    final daysSinceCheckIn = (engagementMetrics['daysSinceCheckIn'] as int?) ?? 0;
    final appointmentRate = (engagementMetrics['appointmentRate'] as double?) ?? 0;
    final weeklyCheckInRate =
        (engagementMetrics['weeklyCheckInRate'] as int?) ?? 0;

    Color riskColor;
    String riskLabel;
    IconData riskIcon;
    
    if (dropoutRisk >= 70) {
      riskColor = Colors.red;
      riskLabel = 'CRITICAL DROPOUT RISK';
      riskIcon = Icons.priority_high_rounded;
    } else if (dropoutRisk >= 50) {
      riskColor = Colors.orange;
      riskLabel = 'HIGH DROPOUT RISK';
      riskIcon = Icons.warning_rounded;
    } else if (dropoutRisk >= 30) {
      riskColor = const Color(0xFFFFA726);
      riskLabel = 'MEDIUM DROPOUT RISK';
      riskIcon = Icons.info_rounded;
    } else {
      riskColor = Colors.green;
      riskLabel = 'LOW DROPOUT RISK';
      riskIcon = Icons.check_circle_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: riskColor.withValues(alpha: 0.3),
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
                  color: riskColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: riskColor, width: 1.5),
                ),
                child: Text(
                  riskLabel.replaceAll(' ', ' '),
                  style: TextStyle(
                    color: riskColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Dropout Risk Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(riskIcon, color: riskColor, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Dropout Risk',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$dropoutRisk%',
                    style: TextStyle(
                      color: riskColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: dropoutRisk / 100,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Engagement Metrics Grid
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _buildMetricCard(
                'Days Since Check-in',
                '$daysSinceCheckIn',
                daysSinceCheckIn > 14
                    ? Colors.red
                    : daysSinceCheckIn > 7
                        ? const Color(0xFFFFA726)
                        : Colors.green,
                Icons.calendar_today_rounded,
              ),
              _buildMetricCard(
                'Appointment Rate',
                '${(appointmentRate * 100).toStringAsFixed(0)}%',
                appointmentRate >= 0.8
                    ? Colors.green
                    : appointmentRate >= 0.5
                        ? const Color(0xFFFFA726)
                        : Colors.red,
                Icons.event_rounded,
              ),
              _buildMetricCard(
                'Weekly Check-ins',
                '$weeklyCheckInRate',
                weeklyCheckInRate >= 5
                    ? Colors.green
                    : weeklyCheckInRate >= 2
                        ? const Color(0xFFFFA726)
                        : Colors.red,
                Icons.check_circle_rounded,
              ),
              _buildMetricCard(
                'Engagement Score',
                '${(100 - dropoutRisk).toStringAsFixed(0)}/100',
                riskColor,
                Icons.trending_up_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Last Updated
          Text(
            'Last calculated: just now',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
