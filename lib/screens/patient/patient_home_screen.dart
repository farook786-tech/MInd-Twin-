import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../chat/chat_screen.dart';
import 'daily_checkin_screen.dart';
import 'ethics_control_screen.dart';
import 'my_twin_screen.dart';
import 'patient_ai_chat_screen.dart';
import 'phq9_assessment_screen.dart';
import 'safety_resources_screen.dart';
import 'voice_journal_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  int _currentIndex = 0;

  String? get _patientId => FirebaseAuth.instance.currentUser?.uid;

  DateTime _todayMidnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String? _toStringOrNull(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream(String patientId) {
    return _firestore.collection('users').doc(patientId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _dailyLogsStream(String patientId) {
    return _firestore
        .collection('daily_logs')
        .where('patientId', isEqualTo: patientId)
        .limit(10)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _latestTwoDailyLogsStream(String patientId) {
    return _dailyLogsStream(patientId);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _lastSevenLogsStream(String patientId) {
    return _dailyLogsStream(patientId);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _todayCheckInStream(String patientId) {
    return _dailyLogsStream(patientId);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _todayAppointmentStream(String patientId) {
    return _firestore
        .collection('appointments')
        .where('patientId', isEqualTo: patientId)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_todayMidnight()))
        .limit(10)
      .snapshots();
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  _RiskBand _riskBand(double score) {
    if (score <= 24) {
      return const _RiskBand(
        color: AppTheme.safeGreen,
        label: 'Low Risk',
        emoji: '😊',
      );
    }
    if (score <= 49) {
      return const _RiskBand(
        color: AppTheme.warningAmber,
        label: 'Moderate',
        emoji: '😐',
      );
    }
    if (score <= 74) {
      return const _RiskBand(
        color: Color(0xFFFF9800),
        label: 'High Risk',
        emoji: '😔',
      );
    }
    return const _RiskBand(
      color: AppTheme.riskRed,
      label: 'Critical',
      emoji: '😰',
    );
  }

  String _riskLevelForUserField(double score) {
    if (score <= 24) return 'low';
    if (score <= 49) return 'moderate';
    if (score <= 74) return 'high';
    return 'critical';
  }

  String _trendText(double latest, double previous) {
    if (latest < previous) {
      return '↑ Better';
    }
    if (latest > previous) {
      return '↓ Higher';
    }
    return '→ Same';
  }

  Future<int> _calculateAndPersistStreak(String patientId) async {
    final now = DateTime.now();
    final startWindow = now.subtract(const Duration(days: 400));

    final snapshot = await _firestore
        .collection('daily_logs')
        .where('patientId', isEqualTo: patientId)
        .limit(400)
        .get();

    final loggedDates = <DateTime>{};
    for (final doc in snapshot.docs) {
      final ts = doc.data()['timestamp'];
      if (ts is! Timestamp) continue;
      final d = ts.toDate();
      if (d.isBefore(startWindow)) continue;
      loggedDates.add(DateTime(d.year, d.month, d.day));
    }

    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    while (loggedDates.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    await _firestore.collection('users').doc(patientId).set({
      'streak': streak,
      'lastStreakUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return streak;
  }

  String _streakText(int? streak) {
    if (streak == null || streak == 0) {
      return 'Start your streak today! 💙';
    }
    if (streak == 1) {
      return '🔥 Day 1 streak!';
    }
    if (streak >= 7) {
      return '🏆 Day $streak — Amazing!';
    }
    return '🔥 Day $streak streak!';
  }

  String _allyMessage({
    required String patientName,
    required DateTime? lastCheckInDate,
    required double? latestRiskScore,
  }) {
    final now = DateTime.now();
    final isMorning = now.hour < 12;
    final isEvening = now.hour >= 18;
    final checkedInToday =
        lastCheckInDate != null && _isSameDay(lastCheckInDate.toLocal(), now.toLocal());

    if (!checkedInToday && isMorning) {
      return 'Good morning $patientName! Ready to start your check-in? 💙';
    }

    if (!checkedInToday && isEvening) {
      return 'Hey $patientName, you have not checked in yet. How are you feeling? 💙';
    }

    if (checkedInToday && latestRiskScore != null && latestRiskScore >= 75) {
      return 'I am concerned about you $patientName. Please reach out to your therapist 💙';
    }

    if (checkedInToday && latestRiskScore != null && latestRiskScore >= 50) {
      return 'I see today is a bit tough $patientName. I am here if you need me 💙';
    }

    if (checkedInToday && latestRiskScore != null && latestRiskScore < 50) {
      return 'Great job checking in $patientName! You are doing well today 🌟';
    }

    return 'I am here for you today 💙';
  }

  Future<void> _openCheckIn() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DailyCheckInScreen()),
    );
  }

  Future<void> _openAllyChat() async {
    final patientId = _patientId;
    if (patientId == null) return;

    final userDoc = await _firestore.collection('users').doc(patientId).get();
    final patientName = _toStringOrNull(userDoc.data()?['name']) ?? 'Name unavailable';

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientAIChatScreen(
          patientId: patientId,
          patientName: patientName,
        ),
      ),
    );
  }

  Future<void> _openMessages() async {
    final patientId = _patientId;
    if (patientId == null) return;

    final userDoc = await _firestore.collection('users').doc(patientId).get();
    final userData = userDoc.data();
    final therapistId = _toStringOrNull(userData?['therapistId']);

    if (therapistId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Therapist is not assigned yet.')),
      );
      return;
    }

    final therapistDoc = await _firestore.collection('users').doc(therapistId).get();
    final therapistName =
        _toStringOrNull(therapistDoc.data()?['name']) ?? 'Therapist name unavailable';

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId: therapistId,
          otherUserName: therapistName,
          isTherapist: false,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppTheme.cardDark,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    );
  }

  Widget _buildGreetingCard(Map<String, dynamic>? userData) {
    final name = _toStringOrNull(userData?['name']) ?? 'Name unavailable';
    final greeting = _timeGreeting();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting, $name',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'I\'m here for you today 💙',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskCard(String patientId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream(patientId),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting &&
            !userSnapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Text(
              'Loading risk score...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          );
        }

        final userData = userSnapshot.data?.data();
        final riskScore = _toDouble(userData?['latestRiskScore']);
        if (riskScore == null) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Complete check-in to see your risk',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _openCheckIn,
                  child: const Text('Start Check-in →'),
                ),
              ],
            ),
          );
        }

        final normalizedRisk = riskScore.clamp(0.0, 100.0);
        final riskBand = _riskBand(normalizedRisk);
        final userRiskLevel = _toStringOrNull(userData?['latestRiskLevel']);
        final riskLevelText = userRiskLevel ?? _riskLevelForUserField(normalizedRisk);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Risk Score',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${normalizedRisk.toStringAsFixed(0)}% ($riskLevelText) ${riskBand.emoji}',
                style: TextStyle(
                  color: riskBand.color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                riskBand.label,
                style: TextStyle(
                  color: riskBand.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _latestTwoDailyLogsStream(patientId),
                builder: (context, trendSnapshot) {
                  if (trendSnapshot.connectionState == ConnectionState.waiting &&
                      !trendSnapshot.hasData) {
                    return Text(
                      'Loading trend...',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                    );
                  }

                  if (trendSnapshot.hasError && !trendSnapshot.hasData) {
                    return Text(
                      'Trend unavailable.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                    );
                  }

                  final docs =
                      trendSnapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  final sorted = docs.toList()
                    ..sort((a, b) {
                      final aTime = _toDateTime(a.data()['timestamp']);
                      final bTime = _toDateTime(b.data()['timestamp']);
                      if (aTime == null || bTime == null) return 0;
                      return bTime.compareTo(aTime);
                    });

                  if (sorted.length < 2) {
                    return const SizedBox.shrink();
                  }

                  final latestRisk = _toDouble(sorted[0].data()['riskScore']);
                  final previousRisk = _toDouble(sorted[1].data()['riskScore']);
                  if (latestRisk == null || previousRisk == null) {
                    return const SizedBox.shrink();
                  }

                  return Text(
                    _trendText(latestRisk, previousRisk),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStreakCard(String patientId, Map<String, dynamic>? userData) {
    final streak = _toInt(userData?['streak']);
    if (streak == null) {
      return FutureBuilder<int>(
        future: _calculateAndPersistStreak(patientId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDecoration(),
              child: const Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDecoration(),
              child: Text(
                _streakText(0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          return _buildStreakCard(patientId, {
            ...(userData ?? <String, dynamic>{}),
            'streak': snapshot.data ?? 0,
          });
        },
      );
    }

    final progress = ((streak.toDouble() / 7.0) * 100.0).clamp(0.0, 100.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _streakText(streak),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress / 100.0,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              color: AppTheme.primaryIndigo,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${progress.toStringAsFixed(0)}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChartCard(String patientId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _lastSevenLogsStream(patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Text(
              'Loading chart data...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          );
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Text(
              'Could not load chart data.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final sortedDocs = docs.toList()
          ..sort((a, b) {
            final aTime = a.data()['timestamp'] as Timestamp?;
            final bTime = b.data()['timestamp'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return aTime.compareTo(bTime);
          });

        if (sortedDocs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Text(
              'Complete check-ins to see your chart 📊',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
          );
        }

        final logs = sortedDocs.length > 7
          ? sortedDocs.sublist(sortedDocs.length - 7).map((d) => d.data()).toList()
          : sortedDocs.map((d) => d.data()).toList();
        final moodSpots = <FlSpot>[];
        final sleepSpots = <FlSpot>[];
        final energySpots = <FlSpot>[];
        final riskSpots = <FlSpot>[];
        final dayLabels = <String>[];

        for (var i = 0; i < logs.length; i++) {
          final row = logs[i];
          final mood = _toDouble(row['moodScore']);
          final sleep = _toDouble(row['sleepScore']);
          final energy = _toDouble(row['energyScore']);
          final ts = _toDateTime(row['timestamp']);

          if (mood != null) {
            moodSpots.add(FlSpot(i.toDouble(), (mood / 5.0) * 10.0));
          }
          if (sleep != null) {
            sleepSpots.add(FlSpot(i.toDouble(), (sleep / 4.0) * 10.0));
          }
          if (energy != null) {
            energySpots.add(FlSpot(i.toDouble(), (energy / 4.0) * 10.0));
          }
          final risk = _toDouble(row['riskScore']);
          if (risk != null) {
            riskSpots.add(FlSpot(i.toDouble(), (risk / 10.0).clamp(0.0, 10.0)));
          }

          if (ts == null) {
            dayLabels.add('N/A');
          } else {
            dayLabels.add(DateFormat('EEEE').format(ts));
          }
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: logs.length <= 1 ? 1 : (logs.length - 1).toDouble(),
                    minY: 0,
                    maxY: 10,
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
                            if (index < 0 || index >= dayLabels.length) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              dayLabels[index].substring(0, 3),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
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
              const Wrap(
                spacing: 12,
                children: [
                  _LegendChip(color: Colors.blue, label: 'Mood'),
                  _LegendChip(color: Colors.green, label: 'Sleep'),
                  _LegendChip(color: Colors.purple, label: 'Energy'),
                  _LegendChip(color: Colors.orange, label: 'Risk'),
                ],
              ),
              if (logs.length == 1) ...[
                const SizedBox(height: 8),
                Text(
                  'Check in daily to see your trend 💙',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyTwinScreen()),
                  );
                },
                child: const Text('View Full Twin →'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStartMyDayCard(String patientId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _todayCheckInStream(patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Text(
              'Loading today\'s check-in status...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          );
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Text(
              'Could not verify today\'s check-in.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final checkedInToday = docs.any((doc) {
          final ts = _toDateTime(doc.data()['timestamp']);
          if (ts == null) return false;
          return _isSameDay(ts.toLocal(), DateTime.now().toLocal());
        });

        return Container(
          decoration: _cardDecoration(),
          child: ElevatedButton(
            onPressed: _openCheckIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: checkedInToday ? AppTheme.safeGreen.withValues(alpha: 0.25) : AppTheme.primaryIndigo,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              checkedInToday ? 'View Today\'s Check-in ✓' : '🌅 Start My Day',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    Widget item({
      required String emoji,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: _cardDecoration(),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Column(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        item(
          emoji: '🤖',
          label: 'Talk to Ally',
          onTap: _openAllyChat,
        ),
        item(
          emoji: '📋',
          label: 'PHQ-9 Check',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PHQ9AssessmentScreen()),
            );
          },
        ),
        item(
          emoji: '🛡️',
          label: 'Safety',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SafetyResourcesScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAllyMessageCard(Map<String, dynamic>? userData) {
    final name = _toStringOrNull(userData?['name']) ?? 'there';
    final lastCheckInDate = _toDateTime(userData?['lastCheckInDate']);
    final latestRiskScore = _toDouble(userData?['latestRiskScore']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Text(
        _allyMessage(
          patientName: name,
          lastCheckInDate: lastCheckInDate,
          latestRiskScore: latestRiskScore,
        ),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildAppointmentReminder(String patientId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _todayAppointmentStream(patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Text(
            'Loading appointment reminder...',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
          );
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return Text(
            'Could not load appointment reminder.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
          );
        }

        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final sortedDocs = docs.toList()
          ..sort((a, b) {
            final aTime = _toDateTime(a.data()['scheduledAt']);
            final bTime = _toDateTime(b.data()['scheduledAt']);
            if (aTime == null || bTime == null) return 0;
            return aTime.compareTo(bTime);
          });

        final data = sortedDocs.first.data();
        final scheduledAt = _toDateTime(data['scheduledAt']);
        if (scheduledAt == null || !_isSameDay(scheduledAt.toLocal(), DateTime.now().toLocal())) {
          return const SizedBox.shrink();
        }

        final therapistName = _toStringOrNull(data['therapistName']) ?? 'Therapist name unavailable';
        final timeText = DateFormat('hh:mm a').format(scheduledAt);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Text(
            '📅 Session with $therapistName at $timeText today',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }

  Widget _buildHomeTab(String patientId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream(patientId),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting &&
            !userSnapshot.hasData) {
          return Center(
            child: Text(
              'Loading home data...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          );
        }

        if (userSnapshot.hasError && !userSnapshot.hasData) {
          return Center(
            child: Text(
              'Could not load home data.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          );
        }

        final userData = userSnapshot.data?.data();

        return RefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _buildGreetingCard(userData),
              const SizedBox(height: 14),
              _sectionTitle('Risk Score'),
              _buildRiskCard(patientId),
              const SizedBox(height: 14),
              _sectionTitle('Streak'),
              _buildStreakCard(patientId, userData),
              const SizedBox(height: 14),
              _sectionTitle('My Twin Mini Chart'),
              _buildMiniChartCard(patientId),
              const SizedBox(height: 14),
              _buildStartMyDayCard(patientId),
              const SizedBox(height: 14),
              _sectionTitle('Quick Actions'),
              _buildQuickActions(),
              const SizedBox(height: 14),
              _sectionTitle('Ally Message'),
              _buildAllyMessageCard(userData),
              const SizedBox(height: 14),
              _buildAppointmentReminder(patientId),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientId = _patientId;

    final tabs = <Widget>[
      if (patientId == null)
        const Center(child: Text('Please sign in to view your home.'))
      else
        _buildHomeTab(patientId),
      const VoiceJournalScreen(),
      const MyTwinScreen(),
      const EthicsControlScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: const Text('🧠 MindTwin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy),
            tooltip: 'Ally',
            onPressed: _openAllyChat,
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Messages',
            onPressed: _openMessages,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: tabs[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        backgroundColor: AppTheme.cardDark,
        indicatorColor: AppTheme.primaryIndigo.withValues(alpha: 0.3),
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.mic_none), label: 'Journal'),
          NavigationDestination(icon: Icon(Icons.auto_graph), label: 'My Twin'),
          NavigationDestination(icon: Icon(Icons.privacy_tip_outlined), label: 'Privacy'),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendChip({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
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
}

class _RiskBand {
  final Color color;
  final String label;
  final String emoji;

  const _RiskBand({
    required this.color,
    required this.label,
    required this.emoji,
  });
}
