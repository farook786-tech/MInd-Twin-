import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'daily_checkin_screen.dart';

class MyTwinScreen extends StatefulWidget {
  const MyTwinScreen({super.key});

  @override
  State<MyTwinScreen> createState() => _MyTwinScreenState();
}

class _MyTwinScreenState extends State<MyTwinScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int? _selectedChartIndex;
  int _refreshVersion = 0;

  @override
  void initState() {
    super.initState();
    _refreshVersion = 1;
  }

  String? get _patientId => FirebaseAuth.instance.currentUser?.uid;

  void _refreshStreams() {
    if (!mounted) return;
    setState(() {
      _refreshVersion += 1;
      _selectedChartIndex = null;
    });
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _lastSevenLogsFallback(String patientId) {
    try {
      return _firestore
          .collection('daily_logs')
          .where('patientId', isEqualTo: patientId)
          .limit(7)
          .snapshots();
    } catch (_) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _lastSevenLogs(String patientId) {
    try {
      return _firestore
          .collection('daily_logs')
          .where('patientId', isEqualTo: patientId)
          .limit(7)
          .snapshots();
    } catch (_) {
      return _lastSevenLogsFallback(patientId);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _latestLogFallback(String patientId) {
    try {
      return _firestore
          .collection('daily_logs')
          .where('patientId', isEqualTo: patientId)
          .limit(10)
          .snapshots();
    } catch (_) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _latestLog(String patientId) {
    try {
      return _firestore
          .collection('daily_logs')
          .where('patientId', isEqualTo: patientId)
          .limit(10)
          .snapshots();
    } catch (_) {
      return _latestLogFallback(patientId);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _latestClinicalAssessments(String patientId) {
    try {
      return _firestore
          .collection('clinical_assessments')
          .where('patientId', isEqualTo: patientId)
          .limit(5)
          .snapshots();
    } catch (_) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
  }

  _RiskBand _riskBand(double score) {
    if (score <= 24) {
      return const _RiskBand(label: 'Low Risk', color: AppTheme.safeGreen);
    }
    if (score <= 49) {
      return const _RiskBand(label: 'Moderate', color: AppTheme.warningAmber);
    }
    if (score <= 74) {
      return const _RiskBand(label: 'High Risk', color: Color(0xFFFF9800));
    }
    return const _RiskBand(label: 'Critical', color: AppTheme.riskRed);
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(List<_TwinPoint> points) {
    final sorted = List<_TwinPoint>.from(points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final moodSpots = <FlSpot>[];
    final sleepSpots = <FlSpot>[];
    final energySpots = <FlSpot>[];
    final riskSpots = <FlSpot>[];

    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (p.moodScore != null) {
        moodSpots.add(FlSpot(i.toDouble(), (p.moodScore! / 5.0) * 10.0));
      }
      if (p.sleepScore != null) {
        sleepSpots.add(FlSpot(i.toDouble(), (p.sleepScore! / 4.0) * 10.0));
      }
      if (p.energyScore != null) {
        energySpots.add(FlSpot(i.toDouble(), (p.energyScore! / 4.0) * 10.0));
      }
      if (p.riskScore != null) {
        riskSpots.add(FlSpot(i.toDouble(), (p.riskScore! / 10.0).clamp(0.0, 10.0)));
      }
    }

    final selectedIndex = _selectedChartIndex != null &&
            _selectedChartIndex! >= 0 &&
            _selectedChartIndex! < sorted.length
        ? _selectedChartIndex!
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '7-Day Mood, Sleep, Energy & Risk',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sorted.length == 1) ...[
            const SizedBox(height: 6),
            Text(
              'Check in daily to see your trend 💙',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: sorted.length <= 1 ? 1 : (sorted.length - 1).toDouble(),
                minY: 0,
                maxY: 10,
                clipData: const FlClipData.all(),
                lineTouchData: LineTouchData(
                  touchTooltipData: const LineTouchTooltipData(
                    tooltipBgColor: Colors.black87,
                  ),
                  touchCallback: (event, response) {
                    if (event is FlTapUpEvent || event is FlPanEndEvent) {
                      if (response?.lineBarSpots == null || response!.lineBarSpots!.isEmpty) {
                        return;
                      }
                      setState(() {
                        _selectedChartIndex = response.lineBarSpots!.first.x.toInt();
                      });
                    }
                  },
                ),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 2,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.1),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 2,
                      reservedSize: 26,
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        final index = value.toInt();
                        if (index < 0 || index >= sorted.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          DateFormat('EEE').format(sorted[index].timestamp),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: moodSpots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: sleepSpots,
                    isCurved: true,
                    color: Colors.green,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: energySpots,
                    isCurved: true,
                    color: Colors.purple,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: riskSpots,
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            children: [
              _legend(Colors.blue, 'Mood'),
              _legend(Colors.green, 'Sleep'),
              _legend(Colors.purple, 'Energy'),
              _legend(Colors.orange, 'Risk'),
            ],
          ),
          if (selectedIndex != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEE, MMM d').format(sorted[selectedIndex].timestamp),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _metricRow(
                    'Mood',
                    sorted[selectedIndex].moodScore?.toStringAsFixed(0) ?? 'Unavailable',
                  ),
                  _metricRow(
                    'Sleep',
                    sorted[selectedIndex].sleepScore?.toStringAsFixed(0) ?? 'Unavailable',
                  ),
                  _metricRow(
                    'Energy',
                    sorted[selectedIndex].energyScore?.toStringAsFixed(0) ?? 'Unavailable',
                  ),
                  _metricRow(
                    'Risk',
                    sorted[selectedIndex].riskScore != null
                        ? '${sorted[selectedIndex].riskScore!.toStringAsFixed(0)}%'
                        : 'Unavailable',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskGauge(double? riskScore) {
    if (riskScore == null) {
      return const Column(
        children: [
          Icon(Icons.analytics_outlined, color: Colors.white54, size: 44),
          SizedBox(height: 8),
          Text(
            'Risk score unavailable',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      );
    }

    final clamped = riskScore.clamp(0.0, 100.0);
    final band = _riskBand(clamped);

    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: const Size(200, 200),
          painter: _RiskGaugePainter(riskValue: clamped / 100.0),
        ),
        Column(
          children: [
            Text(
              '${clamped.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              band.label,
              style: TextStyle(
                color: band.color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _sumScores(List<_TwinPoint> points, double? Function(_TwinPoint point) selector) {
    return points.fold<double>(
      0,
      (sum, point) => sum + (selector(point) ?? 0),
    );
  }

  String _trendText(double? latest, double? previous) {
    if (latest == null || previous == null) return 'Trend unavailable';
    if (latest < previous) return '↑ Better than yesterday';
    if (latest > previous) return '↓ Higher than yesterday';
    return '→ Same as yesterday';
  }

  Widget _buildFirstCheckInEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights_outlined, size: 44, color: Colors.white54),
            const SizedBox(height: 14),
            const Text(
              'Complete your first check-in to see your twin! 💙',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DailyCheckInScreen()),
                );
                _refreshStreams();
              },
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: const Text('Start Check-in'),
            ),
          ],
        ),
      ),
    );
  }

  List<_TwinPoint> _toTwinPoints(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final points = <_TwinPoint>[];
    for (final doc in docs) {
      try {
        final data = doc.data();
        final ts = _toDateTime(data['timestamp']);
        if (ts == null) continue;

        points.add(
          _TwinPoint(
            timestamp: ts,
            moodScore: _toDouble(data['moodScore']),
            sleepScore: _toDouble(data['sleepScore']),
            energyScore: _toDouble(data['energyScore']),
            riskScore: _toDouble(data['riskScore']),
            wellbeingScore: _toDouble(data['wellbeingScore']),
          ),
        );
      } catch (_) {
        // Skip malformed entries and continue rendering available data.
      }
    }
    return points;
  }

  _TwinPoint? _latestPointFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    try {
      final points = _toTwinPoints(docs)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return points.isEmpty ? null : points.first;
    } catch (_) {
      return null;
    }
  }

  Widget _buildBodyForLogs(String patientId, List<_TwinPoint> points) {
    final sortedDesc = List<_TwinPoint>.from(points)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final latest = sortedDesc.first;
    final previous = sortedDesc.length > 1 ? sortedDesc[1] : null;
    final dataPoints = sortedDesc.length;

    final moodAverage = dataPoints == 0 ? null : ((_sumScores(sortedDesc, (e) => e.moodScore) / dataPoints) / 5.0) * 10.0;
    final sleepAverage = dataPoints == 0 ? null : ((_sumScores(sortedDesc, (e) => e.sleepScore) / dataPoints) / 4.0) * 10.0;
    final anxietyAverage = dataPoints == 0 ? null : ((_sumScores(sortedDesc, (e) => e.energyScore) / dataPoints) / 4.0) * 10.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChartCard(points),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey<String>('latest-risk-$patientId-$_refreshVersion'),
            stream: _latestLog(patientId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError && !snapshot.hasData) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Text(
                    'Risk score unavailable right now.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final latestPoint = _latestPointFromDocs(docs);
              final riskScore = latestPoint?.riskScore;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Center(child: _buildRiskGauge(riskScore)),
              );
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Latest Daily Check-in',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _metricRow('Mood Score', latest.moodScore?.toStringAsFixed(0) ?? 'Unavailable'),
                _metricRow('Sleep Score', latest.sleepScore?.toStringAsFixed(0) ?? 'Unavailable'),
                _metricRow('Energy Score', latest.energyScore?.toStringAsFixed(0) ?? 'Unavailable'),
                _metricRow(
                  'Wellbeing',
                  latest.wellbeingScore != null
                      ? '${latest.wellbeingScore!.toStringAsFixed(0)}%'
                      : 'Unavailable',
                ),
                _metricRow(
                  'Risk Score',
                  latest.riskScore != null ? '${latest.riskScore!.toStringAsFixed(0)}%' : 'Unavailable',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _latestClinicalAssessments(patientId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: const Text(
                    'Loading latest clinical assessment...',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              if (snapshot.hasError && !snapshot.hasData) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: const Text(
                    'Clinical assessment unavailable.',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (docs.isEmpty) {
                return const SizedBox.shrink();
              }

              final sorted = docs.toList()
                ..sort((a, b) {
                  final aTime = _toDateTime(a.data()['timestamp']);
                  final bTime = _toDateTime(b.data()['timestamp']);
                  if (aTime == null || bTime == null) return 0;
                  return bTime.compareTo(aTime);
                });

              final latestAssessment = sorted.first.data();
              final phq9 = _toDouble(latestAssessment['phq9Score']);
              final gad7 = _toDouble(latestAssessment['gad7Score']);

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Latest Clinical Assessment',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _metricRow('PHQ-9', phq9?.toStringAsFixed(0) ?? 'Unavailable'),
                    _metricRow('GAD-7', gad7?.toStringAsFixed(0) ?? 'Unavailable'),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trend',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _trendText(latest.riskScore, previous?.riskScore),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Data points',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${sortedDesc.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Detailed Metrics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _metricRow(
                  'Mood Avg',
                  moodAverage == null ? 'Unavailable' : '${moodAverage.toStringAsFixed(1)}/10',
                ),
                _metricRow(
                  'Sleep Avg',
                  sleepAverage == null ? 'Unavailable' : '${sleepAverage.toStringAsFixed(1)}/10',
                ),
                _metricRow(
                  'Anxiety Avg',
                  anxietyAverage == null ? 'Unavailable' : '${anxietyAverage.toStringAsFixed(1)}/10',
                ),
                _metricRow('Data Points', '$dataPoints'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientId = _patientId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Digital Twin'),
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
      ),
      body: patientId == null
          ? const Center(
              child: Text(
                'Please sign in to view your twin.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey<String>('my-twin-logs-$patientId-$_refreshVersion'),
              stream: _lastSevenLogs(patientId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
                  );
                }

                if (snapshot.hasError && !snapshot.hasData) {
                  final errorText = snapshot.error?.toString() ?? 'Unknown error';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Failed to load twin data: $errorText',
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                if (docs.isEmpty) {
                  return _buildFirstCheckInEmptyState();
                }

                final points = _toTwinPoints(docs);

                if (points.isEmpty) {
                  return _buildFirstCheckInEmptyState();
                }

                return _buildBodyForLogs(patientId, points);
              },
            ),
    );
  }
}

class _TwinPoint {
  final DateTime timestamp;
  final double? moodScore;
  final double? sleepScore;
  final double? energyScore;
  final double? riskScore;
  final double? wellbeingScore;

  const _TwinPoint({
    required this.timestamp,
    required this.moodScore,
    required this.sleepScore,
    required this.energyScore,
    required this.riskScore,
    required this.wellbeingScore,
  });
}

class _RiskBand {
  final String label;
  final Color color;

  const _RiskBand({
    required this.label,
    required this.color,
  });
}

class _RiskGaugePainter extends CustomPainter {
  final double riskValue;

  _RiskGaugePainter({required this.riskValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final color = riskValue >= 0.75
        ? AppTheme.riskRed
        : (riskValue >= 0.50 ? AppTheme.warningAmber : AppTheme.safeGreen);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159,
      riskValue * 3.14159,
      false,
      paint,
    );

    canvas.drawCircle(
      center,
      radius + 12,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RiskGaugePainter oldDelegate) {
    return oldDelegate.riskValue != riskValue;
  }
}
