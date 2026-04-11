import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/auth_service.dart';

class EngagementReminderStatsScreen extends StatefulWidget {
  const EngagementReminderStatsScreen({super.key});

  @override
  State<EngagementReminderStatsScreen> createState() =>
      _EngagementReminderStatsScreenState();
}

class _EngagementReminderStatsScreenState
    extends State<EngagementReminderStatsScreen> {
  final BackendApiService _backendApiService = BackendApiService();
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _stats;
  bool _isLoading = false;
  String? _therapistId;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _therapistId = _authService.currentUserId ?? 'therapist_main';
      if (_therapistId != null) {
        await _loadStats();
      }
    } catch (e) {
      print('Error initializing: $e');
    }
  }

  Future<void> _loadStats() async {
    if (_therapistId == null) return;

    setState(() => _isLoading = true);

    try {
      final stats = await _backendApiService.getReminderStats(_therapistId!);
      if (!mounted) return;

      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading stats: $e')),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.notifications_rounded,
                      color: Colors.purple, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Reminder Analytics',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Engagement reminder performance metrics',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 14, bottom: 14),
            child: ElevatedButton.icon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.indigo),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildKeyMetrics(),
                  const SizedBox(height: 20),
                  _buildRiskBreakdown(),
                  const SizedBox(height: 20),
                  _buildReminderDistribution(),
                  const SizedBox(height: 20),
                  _buildEngagementTrend(),
                  const SizedBox(height: 20),
                  _buildRecommendations(),
                ],
              ),
            ),
    );
  }

  Widget _buildKeyMetrics() {
    if (_stats == null) {
      return const SizedBox.shrink();
    }

    final totalReminders = _stats!['total_sent'] ?? 0;
    final avgDropoutRisk = (_stats!['avg_dropout_risk'] ?? 0).toStringAsFixed(1);
    final criticalCount = _stats!['critical_count'] ?? 0;
    final highCount = _stats!['high_count'] ?? 0;

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
            'Key Metrics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Total Reminders',
                  totalReminders.toString(),
                  Icons.send_rounded,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  'Avg Dropout Risk',
                  '$avgDropoutRisk%',
                  Icons.trending_up_rounded,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Critical Risk',
                  criticalCount.toString(),
                  Icons.warning_rounded,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  'High Risk',
                  highCount.toString(),
                  Icons.notification_important_rounded,
                  Colors.yellow[700]!,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskBreakdown() {
    if (_stats == null) {
      return const SizedBox.shrink();
    }

    final riskLevels = _stats!['risk_distribution'] as Map<String, dynamic>?;
    if (riskLevels == null) {
      return const SizedBox.shrink();
    }

    List<MapEntry<String, int>> sortedRisks = riskLevels.entries
        .map((e) => MapEntry(e.key, e.value as int))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Risk Distribution',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'All Patients',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: sortedRisks.map((entry) {
              final level = entry.key;
              final count = entry.value;
              final total = sortedRisks.fold<int>(0, (sum, e) => sum + e.value);
              final percentage = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0';

              Color levelColor;
              switch (level) {
                case 'critical':
                  levelColor = Colors.red;
                  break;
                case 'high':
                  levelColor = Colors.orange;
                  break;
                case 'medium':
                  levelColor = Colors.yellow[700]!;
                  break;
                case 'low':
                default:
                  levelColor = Colors.green;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: levelColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              level.toUpperCase(),
                              style: TextStyle(
                                color: levelColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$count patients ($percentage%)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total > 0 ? count / total : 0,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(levelColor),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderDistribution() {
    if (_stats == null) {
      return const SizedBox.shrink();
    }

    final byFrequency = _stats!['reminders_by_frequency'] as Map<String, dynamic>?;
    if (byFrequency == null) {
      return const SizedBox.shrink();
    }

    final frequencies = [
      MapEntry(
        '3-Day (Critical)',
        (byFrequency['critical_3day'] ?? 0) as int,
      ),
      MapEntry(
        '5-Day (High)',
        (byFrequency['high_5day'] ?? 0) as int,
      ),
      MapEntry(
        'Weekly (Medium)',
        (byFrequency['medium_weekly'] ?? 0) as int,
      ),
      MapEntry(
        'Bi-Weekly (Low)',
        (byFrequency['low_biweekly'] ?? 0) as int,
      ),
    ];

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
            'Reminders by Schedule',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Active reminders grouped by frequency tier',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 16),
          Column(
            children: frequencies.asMap().entries.map((entry) {
              final index = entry.key;
              final freq = entry.value;
              final count = freq.value;

              final colors = [Colors.red, Colors.orange, Colors.yellow[700]!, Colors.green];
              final color = colors[index];

              return Padding(
                padding: EdgeInsets.only(
                  bottom: index != frequencies.length - 1 ? 12 : 0,
                ),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getFrequencyIcon(freq.key),
                            color: color,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            freq.key,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$count patients',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  IconData _getFrequencyIcon(String frequency) {
    if (frequency.contains('3-Day')) return Icons.flash_on;
    if (frequency.contains('5-Day')) return Icons.local_fire_department_rounded;
    if (frequency.contains('Weekly')) return Icons.calendar_today_rounded;
    return Icons.schedule_rounded;
  }

  Widget _buildEngagementTrend() {
    if (_stats == null) {
      return const SizedBox.shrink();
    }

    final lastReminderTime = _stats!['last_reminder_time'] ?? 'Unknown';

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
            'System Status',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Reminder Engine',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Last evaluation: $lastReminderTime',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Text(
              'ℹ Reminders are evaluated every 30 minutes automatically. '
              'Frequency adjusts based on each patient\'s real-time dropout risk.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendations() {
    if (_stats == null) {
      return const SizedBox.shrink();
    }

    final avgDropoutRisk = _stats!['avg_dropout_risk'] ?? 0;
    final criticalCount = _stats!['critical_count'] ?? 0;

    List<String> recommendations = [];

    if (avgDropoutRisk > 50) {
      recommendations.add('⚠ Average dropout risk is HIGH - consider increase in manual check-ins');
    }

    if (criticalCount > 5) {
      recommendations.add('🔴 Multiple critical-risk patients present - prioritize interventions');
    }

    if (recommendations.isEmpty) {
      recommendations.add('✓ Reminder system operating normally - keep monitoring');
    }

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
            'Recommendations',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: recommendations.map((rec) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  rec,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
