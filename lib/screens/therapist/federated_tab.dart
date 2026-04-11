import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/database_service.dart';

class FederatedTab extends StatefulWidget {
  const FederatedTab({super.key});

  @override
  State<FederatedTab> createState() => _FederatedTabState();
}

class _FederatedTabState extends State<FederatedTab> {
  final DatabaseService _dbService = DatabaseService();
  final BackendApiService _backendApiService = BackendApiService();

  bool _loading = true;
  int _localPatientCount = 0;
  List<Map<String, dynamic>> _sharedAppointments = const [];
  List<Map<String, dynamic>> _sharedTreatmentPlans = const [];

  @override
  void initState() {
    super.initState();
    _loadHubData();
  }

  Future<void> _loadHubData() async {
    setState(() => _loading = true);
    try {
      final patients = await _dbService.getAllPatients();
      final appointments = await _backendApiService.fetchSharedAppointments();
      final plans = await _backendApiService.fetchSharedTreatmentPlans();

      if (!mounted) return;
      setState(() {
        _localPatientCount = patients.length;
        _sharedAppointments = appointments;
        _sharedTreatmentPlans = plans;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _deliveredAppointments {
    return _sharedAppointments.where((a) {
      final status = (a['status'] ?? 'scheduled').toString().toLowerCase();
      return status == 'scheduled' || status == 'completed';
    }).length;
  }

  int get _activePlans {
    return _sharedTreatmentPlans.where((p) {
      return (p['status'] ?? 'active').toString().toLowerCase() == 'active';
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadHubData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildKpiRow(),
          const SizedBox(height: 16),
          _buildActionCard(),
          const SizedBox(height: 16),
          _buildRecentTreatmentPlans(),
          const SizedBox(height: 16),
          _buildRecentAppointments(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Care Transfer Hub',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Track what has been sent from therapist tools to patient apps.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow() {
    return Row(
      children: [
        Expanded(
          child: _buildKpiCard('Local Patients', '$_localPatientCount', AppTheme.primaryIndigo),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildKpiCard('Plans Sent', '${_sharedTreatmentPlans.length}', Colors.teal),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildKpiCard('Appointments Sent', '$_deliveredAppointments', Colors.orange),
        ),
      ],
    );
  }

  Widget _buildKpiCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Therapist Workflow',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            '1. Create treatment plan or appointment in patient tools.\n'
            '2. Confirm "Send to patient" when prompted.\n'
            '3. Verify delivery records below in this hub.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72), height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Active Plans: $_activePlans',
                  style: const TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Scheduled Visits: $_deliveredAppointments',
                  style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTreatmentPlans() {
    return _buildSection(
      title: 'Recent Sent Treatment Plans',
      emptyText: 'No treatment plan has been sent yet.',
      count: _sharedTreatmentPlans.length,
      children: _sharedTreatmentPlans.take(5).map((plan) {
        final diagnosis = (plan['primary_diagnosis'] ?? 'Treatment Plan').toString();
        final patientName = (plan['patient_name'] ?? 'Patient').toString();
        final approach = (plan['treatment_approach'] ?? 'Not specified').toString();
        final patientSeen = (plan['patient_seen'] as num?)?.toInt() ?? 0;
        final patientAccepted = (plan['patient_accepted'] as num?)?.toInt() ?? 0;
        return _buildListRow(
          title: diagnosis,
          subtitle: '$patientName  $approach',
          badge: (plan['status'] ?? 'active').toString().toUpperCase(),
          badgeColor: Colors.teal,
          patientSeen: patientSeen == 1,
          patientAccepted: patientAccepted == 1,
        );
      }).toList(),
    );
  }

  Widget _buildRecentAppointments() {
    return _buildSection(
      title: 'Recent Sent Appointments',
      emptyText: 'No appointment has been sent yet.',
      count: _sharedAppointments.length,
      children: _sharedAppointments.take(6).map((item) {
        final patientName = (item['patient_name'] ?? 'Patient').toString();
        final scheduled = (item['scheduled_at'] ?? 'TBD').toString();
        final type = (item['type'] ?? 'followup').toString();
        final patientSeen = (item['patient_seen'] as num?)?.toInt() ?? 0;
        final patientAccepted = (item['patient_accepted'] as num?)?.toInt() ?? 0;
        return _buildListRow(
          title: patientName,
          subtitle: '$scheduled  $type',
          badge: (item['status'] ?? 'scheduled').toString().toUpperCase(),
          badgeColor: Colors.orange,
          patientSeen: patientSeen == 1,
          patientAccepted: patientAccepted == 1,
        );
      }).toList(),
    );
  }

  Widget _buildSection({
    required String title,
    required String emptyText,
    required int count,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (children.isEmpty)
            Text(
              emptyText,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
            )
          else
            ...children,
        ],
      ),
    );
  }

  Widget _buildListRow({
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    bool patientSeen = false,
    bool patientAccepted = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
                      ),
                    ),
                    Row(
                      children: [
                        if (patientSeen)
                          Row(
                            children: [
                              Icon(Icons.check_circle, size: 12, color: Colors.green.shade400),
                              const SizedBox(width: 3),
                              Text(
                                'Seen',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade400,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        else
                          Icon(Icons.circle_outlined, size: 12, color: Colors.white.withValues(alpha: 0.3)),
                        if (patientAccepted) ...[
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              Icon(Icons.check_circle, size: 12, color: Colors.teal.shade400),
                              const SizedBox(width: 3),
                              Text(
                                'Accepted',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.teal.shade400,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: badgeColor.withValues(alpha: 0.6)),
            ),
            child: Text(
              badge,
              style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
