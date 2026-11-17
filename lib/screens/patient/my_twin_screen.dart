import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/twin_chart.dart';
import '../../services/auth_service.dart';
import '../../services/wearable_sync_service.dart';
import '../../widgets/patient_vitals_panel.dart';
import 'daily_checkin_screen.dart';

class MyTwinScreen extends StatefulWidget {
  const MyTwinScreen({super.key});

  @override
  State<MyTwinScreen> createState() => _MyTwinScreenState();
}

class _MyTwinScreenState extends State<MyTwinScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  int? _selectedChartIndex;
  int _refreshVersion = 0;

  @override
  void initState() {
    super.initState();
    _refreshVersion = 1;
  }

  String? get _patientId => _authService.currentUserId;

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

  Widget _buildChartCard(List<_TwinPoint> points) {
    final sorted = List<_TwinPoint>.from(points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final chartPoints = sorted
        .map(
          (p) => TwinChartPoint(
            timestamp: p.timestamp,
            mood: p.moodScore,
            sleep: p.sleepScore,
            energy: p.energyScore,
            risk: p.riskScore,
          ),
        )
        .toList();

    final selectedIndex = _selectedChartIndex != null &&
            _selectedChartIndex! >= 0 &&
            _selectedChartIndex! < sorted.length
        ? _selectedChartIndex!
        : null;

    return AppCard(
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
          TwinTrendChart(
            points: chartPoints,
            height: 200,
            selectedIndex: selectedIndex,
            onPointSelected: (index) {
              setState(() {
                _selectedChartIndex = index;
              });
            },
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
      (total, point) => total + (selector(point) ?? 0),
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
        child: EmptyState(
          emoji: '🧬',
          message: 'Complete your first check-in to see your twin! 💙',
          action: ElevatedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DailyCheckInScreen()),
              );
              _refreshStreams();
            },
            icon: const Icon(Icons.playlist_add_check_rounded),
            label: const Text('Start Check-in'),
          ),
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
                return const AppCard(child: Center(child: CircularProgressIndicator()));
              }

              if (snapshot.hasError && !snapshot.hasData) {
                return const AppCard(
                  child: Text(
                    'Risk score unavailable right now.',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final latestPoint = _latestPointFromDocs(docs);
              final riskScore = latestPoint?.riskScore;

              return AppCard(child: Center(child: _buildRiskGauge(riskScore)));
            },
          ),
          const SizedBox(height: 20),
          AppCard(
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
          _buildWearableVitalsCard(),
          const SizedBox(height: 20),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _latestClinicalAssessments(patientId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const AppCard(
                  child: Text(
                    'Loading latest clinical assessment...',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              if (snapshot.hasError && !snapshot.hasData) {
                return const AppCard(
                  child: Text(
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

              return AppCard(
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
          AppCard(
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
          AppCard(
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

  Future<void> _runWatchAction(Future<String?> Function() action, String successMessage) async {
    final error = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? successMessage),
        backgroundColor: error == null ? AppTheme.safeGreen : AppTheme.warningAmber,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Widget _buildWearableVitalsCard() {
    final patientId = _patientId;
    if (patientId == null) return const SizedBox.shrink();
    final syncService = WearableSyncService();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Real watch connection state (Wear OS Data Layer capability), never assumed.
        ValueListenableBuilder<WatchStatus?>(
          valueListenable: syncService.watchStatus,
          builder: (context, status, _) {
            final connected = status?.connected == true;
            final label = status == null
                ? 'Watch status unknown'
                : connected
                    ? 'Watch connected${status.nodeNames.isNotEmpty ? ' · ${status.nodeNames.first}' : ''}'
                    : status.pairedNodeConnected
                        ? 'Watch reachable, MindTwin watch app not installed'
                        : 'Watch not connected';
            final color = connected ? AppTheme.safeGreen : AppTheme.warningAmber;
            // "Link your watch" guidance: the watch component is part of this app.
            final String? hint;
            final Widget? action;
            if (status == null) {
              hint = null;
              action = null;
            } else if (connected) {
              hint = 'Heart rate is shared with your therapist automatically. '
                  'If no readings appear, open MindTwin on the watch and allow heart-rate access.';
              action = TextButton.icon(
                onPressed: () => _runWatchAction(syncService.openOnWatch,
                    'MindTwin opened on your watch. Allow heart-rate access there ("Allow all the time").'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open on watch'),
              );
            } else if (status.pairedNodeConnected) {
              hint = 'Your watch is paired. Install MindTwin on it to share heart rate with your therapist.';
              action = TextButton.icon(
                onPressed: () => _runWatchAction(syncService.installOnWatch,
                    'Check your watch: tap Install, then open MindTwin and allow heart-rate access.'),
                icon: const Icon(Icons.install_mobile, size: 16),
                label: const Text('Install on watch'),
              );
            } else {
              hint = 'Pair your Wear OS / Galaxy Watch with your phone (Galaxy Wearable app), keep it '
                  'nearby, then tap refresh. Any watch that syncs to Health Connect (e.g. via '
                  'Samsung Health or Fitbit) also works: allow Health Connect below.';
              action = null;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(connected ? Icons.watch_rounded : Icons.watch_off_outlined, color: color, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: 'Check again',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh, size: 18, color: Colors.white54),
                        onPressed: () {
                          syncService.refreshWatchStatus();
                          syncService.syncNow();
                        },
                      ),
                    ],
                  ),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Text(hint, style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.35)),
                    ),
                  if (action != null)
                    Padding(padding: const EdgeInsets.only(left: 18), child: action),
                ],
              ),
            );
          },
        ),
        ValueListenableBuilder<HealthConnectState>(
          valueListenable: syncService.healthConnectState,
          builder: (context, state, _) {
            if (state != HealthConnectState.permissionDenied && state != HealthConnectState.unavailable) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.health_and_safety_outlined, color: AppTheme.warningAmber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state == HealthConnectState.unavailable
                          ? 'Health Connect is not installed: sleep and steps cannot be read.'
                          : 'Health Connect access not granted: sleep and steps are not shared.',
                      style: const TextStyle(color: AppTheme.warningAmber, fontSize: 12),
                    ),
                  ),
                  if (state == HealthConnectState.permissionDenied)
                    TextButton(
                      onPressed: () async {
                        if (await syncService.requestHealthPermissions()) {
                          await syncService.syncNow();
                        }
                      },
                      child: const Text('Allow'),
                    ),
                ],
              ),
            );
          },
        ),
        PatientVitalsPanel(patientId: patientId),
      ],
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
