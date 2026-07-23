import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'appointments_screen.dart';
import 'patients_tab.dart';
import 'real_time_alerts_center_screen.dart';
import 'simulator_tab.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final therapistId = AuthService().currentUserId;

    if (therapistId == null) {
      return _DashboardShell(
        child: _CenteredStateCard(
          icon: Icons.lock_outline_rounded,
          title: 'Authentication Required',
          subtitle: 'Please sign in as therapist to view the clinical dashboard.',
        ),
      );
    }

    final usersRef = FirebaseFirestore.instance.collection('users');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: usersRef.doc(therapistId).snapshots(),
      builder: (context, therapistSnapshot) {
        final therapistName = _safeString(therapistSnapshot.data?.data()?['name'], fallback: 'Therapist');

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: usersRef
              .where('role', isEqualTo: 'patient')
              .where('therapistId', isEqualTo: therapistId)
              .snapshots(),
          builder: (context, patientsSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('crisis_events')
                  .where('therapistId', isEqualTo: therapistId)
                  .where('acknowledged', isEqualTo: false)
                  .snapshots(),
              builder: (context, crisisSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('daily_logs')
                      .where('therapistId', isEqualTo: therapistId)
                      .limit(300)
                      .snapshots(),
                  builder: (context, logsSnapshot) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('daily_logs')
                          .where('therapistId', isEqualTo: therapistId)
                          .limit(30)
                          .snapshots(),
                      builder: (context, moodTrendSnapshot) {
                        final isLoading = therapistSnapshot.connectionState == ConnectionState.waiting ||
                            patientsSnapshot.connectionState == ConnectionState.waiting ||
                            crisisSnapshot.connectionState == ConnectionState.waiting ||
                            logsSnapshot.connectionState == ConnectionState.waiting ||
                            moodTrendSnapshot.connectionState == ConnectionState.waiting;

                        if (isLoading) {
                          return _DashboardShell(
                            child: _CenteredStateCard(
                              icon: Icons.autorenew_rounded,
                              title: 'Loading Clinical Data',
                              subtitle: 'Syncing patient streams and risk analytics...',
                              isLoading: true,
                            ),
                          );
                        }

                        final patientDocs = patientsSnapshot.data?.docs ?? const [];
                        final crisisDocs = crisisSnapshot.data?.docs ?? const [];
                        final logDocs = logsSnapshot.data?.docs ?? const [];
                        final moodDocs = moodTrendSnapshot.data?.docs ?? const [];

                        final hasAnyData = patientDocs.isNotEmpty || crisisDocs.isNotEmpty || logDocs.isNotEmpty;
                        final hasStreamError = therapistSnapshot.hasError ||
                            patientsSnapshot.hasError ||
                            crisisSnapshot.hasError ||
                            logsSnapshot.hasError ||
                            moodTrendSnapshot.hasError;

                        if (hasStreamError && !hasAnyData) {
                          return _DashboardShell(
                            child: _CenteredStateCard(
                              icon: Icons.error_outline_rounded,
                              title: 'Unable To Load Dashboard',
                              subtitle: 'No data is available right now. Please retry in a moment.',
                              tint: AppTheme.riskRed,
                            ),
                          );
                        }

                        final patients = _dedupePatients(patientDocs);
                        final logsByPatient = _groupLogsByPatient(logDocs);
                        final sortedMoodLogs = moodDocs
                            .map((doc) => doc.data())
                            .toList()
                          ..sort((a, b) => _readTimestamp(b).compareTo(_readTimestamp(a)));

                        final totalPatients = patients.length;
                        final highRiskToday = patients.where((p) => _readRiskPercent(p.data) >= 50).length;
                        final checkedInToday = patients.where((p) => _isToday(_readDate(p.data['lastCheckInDate']))).length;
                        final crisisAlerts = crisisDocs.length;

                        final riskBuckets = _riskBucketCounts(patients);
                        final moodSeries = _buildMoodSeries(sortedMoodLogs);

                        return _DashboardShell(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _DashboardHeader(therapistName: therapistName),
                                const SizedBox(height: 14),
                                if (crisisAlerts > 0)
                                  _CrisisAlertBanner(
                                    alertCount: crisisAlerts,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const RealTimeAlertsCenterScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                if (crisisAlerts > 0) const SizedBox(height: 12),
                                _SummaryGrid(
                                  cards: [
                                    _SummaryCardData(
                                      icon: Icons.groups_rounded,
                                      title: 'Total Patients',
                                      value: '$totalPatients',
                                      subtitle: 'Assigned caseload',
                                      color: Colors.white,
                                    ),
                                    _SummaryCardData(
                                      icon: Icons.warning_amber_rounded,
                                      title: 'High Risk Today',
                                      value: '$highRiskToday',
                                      subtitle: 'Risk score >= 50%',
                                      color: AppTheme.warningAmber,
                                    ),
                                    _SummaryCardData(
                                      icon: Icons.verified_rounded,
                                      title: 'Checked In Today',
                                      value: '$checkedInToday',
                                      subtitle: 'Daily compliance',
                                      color: AppTheme.safeGreen,
                                    ),
                                    _SummaryCardData(
                                      icon: Icons.crisis_alert_rounded,
                                      title: 'Crisis Alerts',
                                      value: '$crisisAlerts',
                                      subtitle: 'Unacknowledged',
                                      color: AppTheme.riskRed,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _SectionCard(
                                  title: 'Patient Risk Overview',
                                  child: patients.isEmpty
                                      ? const _InlineMutedState(
                                          text: 'No patients assigned to this therapist yet.',
                                        )
                                      : Column(
                                          children: patients.map((patient) {
                                            final patientId = patient.id;
                                            final patientName = _safeString(patient.data['name'], fallback: 'Unnamed Patient');
                                            final risk = _readRiskPercent(patient.data);
                                            final moodLabel = _safeString(patient.data['latestMood'], fallback: 'Unknown');
                                            final lastCheckin = _relativeTime(_readDate(patient.data['lastCheckInDate']));
                                            final logs = logsByPatient[patientId] ?? const <Map<String, dynamic>>[];
                                            final trend = _riskTrend(logs);

                                            return _RiskRow(
                                              name: patientName,
                                              riskPercent: risk,
                                              emotion: moodLabel,
                                              lastCheckIn: lastCheckin,
                                              trend: trend,
                                            );
                                          }).toList(),
                                        ),
                                ),
                                const SizedBox(height: 16),
                                _SectionCard(
                                  title: 'Patient Risk Distribution',
                                  child: _RiskBarChart(bucketCounts: riskBuckets),
                                ),
                                const SizedBox(height: 16),
                                _SectionCard(
                                  title: 'Emotion Trend (Last 30 Days)',
                                  child: _MoodLineChart(points: moodSeries),
                                ),
                                const SizedBox(height: 16),
                                _SectionCard(
                                  title: 'Quick Actions',
                                  child: _QuickActions(
                                    onPatients: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const PatientsTab()),
                                      );
                                    },
                                    onAlerts: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const RealTimeAlertsCenterScreen(),
                                        ),
                                      );
                                    },
                                    onSimulator: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const SimulatorTab()),
                                      );
                                    },
                                    onAppointments: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const AppointmentsScreen()),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DashboardShell extends StatelessWidget {
  final Widget child;

  const _DashboardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF090A10),
            Color(0xFF0F111A),
            Color(0xFF0A0A0F),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final String therapistName;

  const _DashboardHeader({required this.therapistName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '🧠 MindTwin',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Text(
                'Dr. $therapistName',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Clinical Dashboard',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final List<_SummaryCardData> cards;

  const _SummaryGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.46,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(card.icon, color: card.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      card.title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                card.value,
                style: TextStyle(
                  color: card.color,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                card.subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.48),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCardData {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _SummaryCardData({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });
}

class _CrisisAlertBanner extends StatelessWidget {
  final int alertCount;
  final VoidCallback onTap;

  const _CrisisAlertBanner({
    required this.alertCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.riskRed.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.riskRed, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🚨 $alertCount Crisis Alert(s) Detected',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to view →',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.84),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  final String name;
  final double riskPercent;
  final String emotion;
  final String lastCheckIn;
  final _TrendDirection trend;

  const _RiskRow({
    required this.name,
    required this.riskPercent,
    required this.emotion,
    required this.lastCheckIn,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    final riskColor = _riskColor(riskPercent);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: riskColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${riskPercent.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: riskColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              emotion,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Icon(
                  _trendIcon(trend),
                  color: _trendColor(trend),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    lastCheckIn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 11,
                    ),
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

class _RiskBarChart extends StatelessWidget {
  final Map<String, int> bucketCounts;

  const _RiskBarChart({required this.bucketCounts});

  @override
  Widget build(BuildContext context) {
    final labels = const ['Low', 'Moderate', 'High', 'Critical'];
    final values = labels.map((key) => (bucketCounts[key] ?? 0).toDouble()).toList();
    final maxY = (values.fold<double>(0, (a, b) => a > b ? a : b) + 1).clamp(1, 200).toDouble();

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.white.withValues(alpha: 0.09),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(values.length, (index) {
            final color = switch (index) {
              0 => AppTheme.safeGreen,
              1 => AppTheme.warningAmber,
              2 => const Color(0xFFE37A42),
              _ => AppTheme.riskRed,
            };
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: values[index],
                  width: 24,
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _MoodLineChart extends StatelessWidget {
  final List<FlSpot> points;

  const _MoodLineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _InlineMutedState(text: 'No mood logs available for the last 30 days.');
    }

    return SizedBox(
      height: 230,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 10,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 2,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withValues(alpha: 0.1),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: (points.length / 5).clamp(1, 7).toDouble(),
                getTitlesWidget: (value, meta) {
                  return Text(
                    'D${value.toInt() + 1}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.56),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 2,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points,
              isCurved: true,
              color: AppTheme.accentCyan,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                  radius: 2.4,
                  color: AppTheme.accentCyan,
                  strokeWidth: 1,
                  strokeColor: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.accentCyan.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onPatients;
  final VoidCallback onAlerts;
  final VoidCallback onSimulator;
  final VoidCallback onAppointments;

  const _QuickActions({
    required this.onPatients,
    required this.onAlerts,
    required this.onSimulator,
    required this.onAppointments,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _QuickActionButton(label: '👥 View Patients', onTap: onPatients),
        _QuickActionButton(label: '🔔 Alerts', onTap: onAlerts),
        _QuickActionButton(label: '🧪 Simulator', onTap: onSimulator),
        _QuickActionButton(label: '📅 Appointments', onTap: onAppointments),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.backgroundDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? tint;
  final bool isLoading;

  const _CenteredStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tint,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppTheme.primaryIndigo;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(22),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const CircularProgressIndicator(color: AppTheme.primaryIndigo)
            else
              Icon(icon, color: color, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMutedState extends StatelessWidget {
  final String text;

  const _InlineMutedState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.56),
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PatientLite {
  final String id;
  final Map<String, dynamic> data;

  const _PatientLite({
    required this.id,
    required this.data,
  });
}

enum _TrendDirection { up, down, flat }

List<_PatientLite> _dedupePatients(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final map = <String, _PatientLite>{};
  for (final doc in docs) {
    final data = doc.data();
    final id = _patientIdFromUserDoc(doc.id, data);
    final current = map[id];
    if (current == null || _readTimestamp(data).isAfter(_readTimestamp(current.data))) {
      map[id] = _PatientLite(id: id, data: data);
    }
  }

  final result = map.values.toList()
    ..sort((a, b) => _safeString(a.data['name']).toLowerCase().compareTo(_safeString(b.data['name']).toLowerCase()));
  return result;
}

Map<String, List<Map<String, dynamic>>> _groupLogsByPatient(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final doc in docs) {
    final data = doc.data();
    final patientId = _safeString(
      data['patientId'] ?? data['uid'] ?? data['userId'],
      fallback: doc.id,
    );
    grouped.putIfAbsent(patientId, () => <Map<String, dynamic>>[]).add(data);
  }

  for (final entry in grouped.entries) {
    entry.value.sort((a, b) => _readTimestamp(b).compareTo(_readTimestamp(a)));
    if (entry.value.length > 5) {
      grouped[entry.key] = entry.value.take(5).toList();
    }
  }
  return grouped;
}

Map<String, int> _riskBucketCounts(List<_PatientLite> patients) {
  final counts = <String, int>{
    'Low': 0,
    'Moderate': 0,
    'High': 0,
    'Critical': 0,
  };

  for (final patient in patients) {
    final risk = _readRiskPercent(patient.data);
    if (risk < 25) {
      counts['Low'] = (counts['Low'] ?? 0) + 1;
    } else if (risk < 50) {
      counts['Moderate'] = (counts['Moderate'] ?? 0) + 1;
    } else if (risk < 75) {
      counts['High'] = (counts['High'] ?? 0) + 1;
    } else {
      counts['Critical'] = (counts['Critical'] ?? 0) + 1;
    }
  }

  return counts;
}

List<FlSpot> _buildMoodSeries(List<Map<String, dynamic>> logs) {
  if (logs.isEmpty) {
    return const [];
  }

  final grouped = <String, List<double>>{};

  for (final log in logs) {
    final mood = _toDouble(log['moodScore']);
    if (mood == null) continue;
    final date = _readTimestamp(log);
    final key = '${date.year}-${date.month}-${date.day}';
    grouped.putIfAbsent(key, () => <double>[]).add(mood.clamp(0.0, 10.0));
  }

  final entries = grouped.entries.toList()
    ..sort((a, b) {
      final aDate = DateTime.tryParse('${a.key}T00:00:00') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse('${b.key}T00:00:00') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aDate.compareTo(bDate);
    });

  return List.generate(entries.length, (index) {
    final list = entries[index].value;
    final avg = list.isEmpty ? 0.0 : list.reduce((a, b) => a + b) / list.length;
    return FlSpot(index.toDouble(), avg);
  });
}

String _patientIdFromUserDoc(String docId, Map<String, dynamic> data) {
  final uid = _safeString(data['uid']);
  final patientId = _safeString(data['patientId']);
  if (uid.isNotEmpty) return uid;
  if (patientId.isNotEmpty) return patientId;
  return docId;
}

_TrendDirection _riskTrend(List<Map<String, dynamic>> logs) {
  if (logs.length < 2) {
    return _TrendDirection.flat;
  }

  final latest = _readRiskPercent(logs[0]);
  final previous = _readRiskPercent(logs[1]);
  final delta = latest - previous;

  if (delta > 3) return _TrendDirection.up;
  if (delta < -3) return _TrendDirection.down;
  return _TrendDirection.flat;
}

IconData _trendIcon(_TrendDirection trend) {
  switch (trend) {
    case _TrendDirection.up:
      return Icons.arrow_upward_rounded;
    case _TrendDirection.down:
      return Icons.arrow_downward_rounded;
    case _TrendDirection.flat:
      return Icons.horizontal_rule_rounded;
  }
}

Color _trendColor(_TrendDirection trend) {
  switch (trend) {
    case _TrendDirection.up:
      return AppTheme.riskRed;
    case _TrendDirection.down:
      return AppTheme.safeGreen;
    case _TrendDirection.flat:
      return Colors.white70;
  }
}

double _readRiskPercent(Map<String, dynamic> source) {
  final value = _toDouble(source['latestRiskScore'] ?? source['riskScore'] ?? source['risk']);
  if (value == null) {
    final wellbeing = _toDouble(source['wellbeingScore']);
    if (wellbeing != null) {
      return (100 - wellbeing).clamp(0.0, 100.0);
    }
    return 0;
  }
  if (value <= 1) return (value * 100).clamp(0.0, 100.0);
  return value.clamp(0.0, 100.0);
}

DateTime _readTimestamp(Map<String, dynamic> source) {
  final candidates = [
    source['timestamp'],
    source['lastCheckInDate'],
    source['updatedAt'],
    source['createdAt'],
  ];
  for (final c in candidates) {
    final parsed = _readDate(c);
    if (parsed != null) return parsed;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _readDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

bool _isToday(DateTime? date) {
  if (date == null) return false;
  final now = DateTime.now();
  return date.year == now.year && date.month == now.month && date.day == now.day;
}

String _relativeTime(DateTime? date) {
  if (date == null) return 'No check-in';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} day ago';
  final weeks = (diff.inDays / 7).floor();
  return '$weeks wk ago';
}

Color _riskColor(double riskPercent) {
  if (riskPercent >= 75) return AppTheme.riskRed;
  if (riskPercent >= 50) return const Color(0xFFE37A42);
  if (riskPercent >= 25) return AppTheme.warningAmber;
  return AppTheme.safeGreen;
}

String _safeString(dynamic value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is num) return value.toString();
  return fallback;
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
