import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

class ClinicalAlertsDashboard extends StatefulWidget {
  const ClinicalAlertsDashboard({super.key});

  @override
  State<ClinicalAlertsDashboard> createState() =>
      _ClinicalAlertsDashboardState();
}

class _ClinicalAlertsDashboardState extends State<ClinicalAlertsDashboard> {
  final BackendApiService _backendApiService = BackendApiService();
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _alerts = [];
  Map<String, String> _patientNames = {};
  bool _loading = true;
  String? _therapistId;

  @override
  void initState() {
    super.initState();
    _initializeAndLoad();
  }

  Future<void> _initializeAndLoad() async {
    try {
      _therapistId = _authService.currentUserId ?? 'therapist_main';
      if (_therapistId != null) {
        await _loadAlerts(_therapistId!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadAlerts(String therapistId) async {
    setState(() => _loading = true);
    try {
      final alerts = await _backendApiService.getClinicalAlerts(therapistId);
      final patientNames = <String, String>{};

      // Load patient names from database
      for (final alert in alerts) {
        final patientId = alert['patientId'] as String?;
        if (patientId != null && !patientNames.containsKey(patientId)) {
          try {
            final patients = await _dbService.getAllPatients();
            final patient = patients.firstWhere((p) => p.id == patientId);
            patientNames[patientId] = patient.name;
          } catch (_) {
            patientNames[patientId] = 'Unknown Patient';
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _alerts = alerts.cast<Map<String, dynamic>>();
        _patientNames = patientNames;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _acknowledgeAlert(String alertId) async {
    try {
      await _backendApiService.acknowledgeAlert(alertId);
      if (_therapistId != null) {
        await _loadAlerts(_therapistId!);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert acknowledged')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_rounded,
                  color: Colors.red, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Clinical Alerts',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _therapistId != null
                ? () => _loadAlerts(_therapistId!)
                : null,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh:
                  _therapistId != null ? () => _loadAlerts(_therapistId!) : () async {},
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildAlertsSummary(),
                  const SizedBox(height: 24),
                  _buildAlertsList(),
                ],
              ),
            ),
    );
  }

  Widget _buildAlertsSummary() {
    final critical = _alerts
        .where((a) => a['severity'] == 'critical')
        .length;
    final high = _alerts.where((a) => a['severity'] == 'high').length;
    final acknowledged =
        _alerts.where((a) => a['status'] == 'acknowledged').length;

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
            'Alert Summary',
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
                child: _buildSummaryCard(
                  'Total Alerts',
                  _alerts.length.toString(),
                  Colors.orange,
                  Icons.notifications_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Critical',
                  critical.toString(),
                  Colors.red,
                  Icons.error_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'High',
                  high.toString(),
                  Colors.orange,
                  Icons.warning_amber_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Acknowledged',
                  acknowledged.toString(),
                  Colors.green,
                  Icons.check_circle_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
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

  Widget _buildAlertsList() {
    if (_alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.check_circle,
                size: 64,
                color: Colors.green.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No active alerts',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'All patients are monitored and stable',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group alerts by severity
    final criticalAlerts = _alerts
        .where((a) => a['severity'] == 'critical' && a['status'] != 'acknowledged')
        .toList();
    final highAlerts = _alerts
        .where((a) => a['severity'] == 'high' && a['status'] != 'acknowledged')
        .toList();
    final mediumAlerts = _alerts
        .where((a) => a['severity'] == 'medium' && a['status'] != 'acknowledged')
        .toList();
    final acknowledgedAlerts =
        _alerts.where((a) => a['status'] == 'acknowledged').toList();

    return Column(
      children: [
        if (criticalAlerts.isNotEmpty) ...[
          _buildAlertGroup('Critical Alerts', criticalAlerts, Colors.red),
          const SizedBox(height: 16),
        ],
        if (highAlerts.isNotEmpty) ...[
          _buildAlertGroup('High Priority', highAlerts, Colors.orange),
          const SizedBox(height: 16),
        ],
        if (mediumAlerts.isNotEmpty) ...[
          _buildAlertGroup('Medium Priority', mediumAlerts, const Color(0xFFFFA726)),
          const SizedBox(height: 16),
        ],
        if (acknowledgedAlerts.isNotEmpty) ...[
          _buildAlertGroup('Acknowledged', acknowledgedAlerts, Colors.green),
        ],
      ],
    );
  }

  Widget _buildAlertGroup(
    String title,
    List<Map<String, dynamic>> alerts,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(alerts.length, (index) {
          return _buildAlertCard(alerts[index], color);
        }),
      ],
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert, Color severityColor) {
    final patientId = alert['patientId'] as String?;
    final patientName = patientId != null
        ? (_patientNames[patientId] ?? 'Unknown Patient')
        : 'Unknown Patient';
    final alertType = alert['alertType'] as String? ?? 'Unknown';
    final description = alert['description'] as String? ?? '';
    final triggeredValue = alert['triggeredValue'];
    final thresholdValue = alert['thresholdValue'];
    final status = alert['status'] as String?;
    final createdAt = alert['createdAt'] as String?;
    final alertId = alert['id'] as String?;

    final timeAgo = createdAt != null
        ? _getTimeAgo(DateTime.parse(createdAt))
        : 'Unknown time';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: severityColor.withValues(alpha: 0.3),
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
                      patientName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatAlertType(alertType),
                      style: TextStyle(
                        color: severityColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
                  color: severityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: severityColor, width: 1.5),
                ),
                child: Text(
                  (status ?? 'active').toUpperCase(),
                  style: TextStyle(
                    color: severityColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildMetricBadge(
                  'Triggered',
                  triggeredValue?.toString() ?? 'N/A',
                  Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricBadge(
                  'Threshold',
                  thresholdValue?.toString() ?? 'N/A',
                  severityColor.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricBadge(
                  'Since',
                  timeAgo,
                  Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          if (status != 'acknowledged') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: alertId != null ? () => _acknowledgeAlert(alertId) : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Acknowledge Alert'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: severityColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricBadge(String label, String value, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bgColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAlertType(String type) {
    return type
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }
}
