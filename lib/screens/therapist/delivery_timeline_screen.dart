import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';

class DeliveryTimelineScreen extends StatefulWidget {
  const DeliveryTimelineScreen({super.key});

  @override
  State<DeliveryTimelineScreen> createState() => _DeliveryTimelineScreenState();
}

class _DeliveryTimelineScreenState extends State<DeliveryTimelineScreen> {
  final BackendApiService _backendApiService = BackendApiService();
  
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _treatmentPlans = [];
  bool _loading = true;
  int _sentCount = 0;
  int _seenCount = 0;
  int _acceptedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDeliveryData();
  }

  Future<void> _loadDeliveryData() async {
    setState(() => _loading = true);
    try {
      final appointments = await _backendApiService.fetchSharedAppointments();
      final plans = await _backendApiService.fetchSharedTreatmentPlans();

      int sent = 0;
      int seen = 0;
      int accepted = 0;

      // Count status across appointments
      for (final apt in appointments) {
        sent++;
        if ((apt['patient_seen'] as num?)?.toInt() == 1) seen++;
        if ((apt['patient_accepted'] as num?)?.toInt() == 1) accepted++;
      }

      // Count status across treatment plans
      for (final plan in plans) {
        sent++;
        if ((plan['patient_seen'] as num?)?.toInt() == 1) seen++;
        if ((plan['patient_accepted'] as num?)?.toInt() == 1) accepted++;
      }

      if (!mounted) return;
      setState(() {
        _appointments = appointments;
        _treatmentPlans = plans;
        _sentCount = sent;
        _seenCount = seen;
        _acceptedCount = accepted;
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
              child: const Icon(Icons.timeline,
                  color: AppTheme.primaryIndigo, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Delivery Timeline',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDeliveryData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusOverview(),
                  const SizedBox(height: 24),
                  _buildAppointmentsTimeline(),
                  const SizedBox(height: 24),
                  _buildTreatmentPlansTimeline(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusOverview() {
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
            'Overall Delivery Status',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatusCard(
                  'Sent',
                  _sentCount,
                  Colors.blue,
                  Icons.send_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusCard(
                  'Seen',
                  _seenCount,
                  Colors.green,
                  Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusCard(
                  'Accepted',
                  _acceptedCount,
                  Colors.teal,
                  Icons.verified_user,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String label, int count, Color color, IconData icon) {
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
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appointments (${_appointments.length})',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (_appointments.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No appointments sent yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          )
        else
          Column(
            children: _appointments.map((apt) {
              return _buildDeliveryItem(
                title: (apt['patient_name'] ?? 'Patient').toString(),
                subtitle: DateFormat('MMM dd, yyyy • h:mm a')
                    .format(DateTime.parse(apt['scheduled_at'] ?? '')),
                sentAt: DateTime.parse(apt['created_at'] ?? ''),
                seenAt: apt['seen_at'] != null && apt['seen_at'].toString().isNotEmpty
                    ? DateTime.parse(apt['seen_at'])
                    : null,
                acceptedAt: apt['accepted_at'] != null && apt['accepted_at'].toString().isNotEmpty
                    ? DateTime.parse(apt['accepted_at'])
                    : null,
                type: 'appointment',
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildTreatmentPlansTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Treatment Plans (${_treatmentPlans.length})',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (_treatmentPlans.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No treatment plans sent yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          )
        else
          Column(
            children: _treatmentPlans.map((plan) {
              return _buildDeliveryItem(
                title: (plan['primary_diagnosis'] ?? 'Treatment Plan').toString(),
                subtitle: (plan['patient_name'] ?? 'Patient').toString(),
                sentAt: DateTime.parse(plan['created_at'] ?? ''),
                seenAt: plan['seen_at'] != null && plan['seen_at'].toString().isNotEmpty
                    ? DateTime.parse(plan['seen_at'])
                    : null,
                acceptedAt: plan['accepted_at'] != null && plan['accepted_at'].toString().isNotEmpty
                    ? DateTime.parse(plan['accepted_at'])
                    : null,
                type: 'treatment_plan',
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildDeliveryItem({
    required String title,
    required String subtitle,
    required DateTime sentAt,
    required DateTime? seenAt,
    required DateTime? acceptedAt,
    required String type,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          // Timeline
          _buildTimelineStep(
            label: 'Sent',
            time: sentAt,
            isCompleted: true,
            icon: Icons.send_rounded,
            color: Colors.blue,
          ),
          if (seenAt != null) ...[
            _buildTimelineConnector(),
            _buildTimelineStep(
              label: 'Seen',
              time: seenAt,
              isCompleted: true,
              icon: Icons.check_circle,
              color: Colors.green,
            ),
          ] else ...[
            _buildTimelineConnector(completed: false),
            _buildTimelineStep(
              label: 'Seen',
              time: DateTime.now(),
              isCompleted: false,
              icon: Icons.check_circle,
              color: Colors.grey,
            ),
          ],
          if (acceptedAt != null) ...[
            _buildTimelineConnector(),
            _buildTimelineStep(
              label: 'Accepted',
              time: acceptedAt,
              isCompleted: true,
              icon: Icons.verified_user,
              color: Colors.teal,
            ),
          ] else if (seenAt != null) ...[
            _buildTimelineConnector(completed: false),
            _buildTimelineStep(
              label: 'Accepted',
              time: DateTime.now(),
              isCompleted: false,
              icon: Icons.verified_user,
              color: Colors.grey,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required String label,
    required DateTime time,
    required bool isCompleted,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCompleted ? color.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCompleted ? color : Colors.grey.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isCompleted ? Colors.white : Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isCompleted
                    ? DateFormat('MMM dd, yyyy • h:mm a').format(time)
                    : 'Pending',
                style: TextStyle(
                  color: isCompleted
                      ? Colors.white.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineConnector({bool completed = true}) {
    return Padding(
      padding: const EdgeInsets.only(left: 19),
      child: Container(
        width: 2,
        height: 16,
        color: completed ? Colors.green.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.2),
      ),
    );
  }
}
