import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/twin_chart.dart';
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

  String? get _patientId => _authService.currentUserId;

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
      return 'Ready to start your check-in? 💙';
    }

    if (!checkedInToday && isEvening) {
      return 'You have not checked in yet. How are you feeling? 💙';
    }

    if (checkedInToday && latestRiskScore != null && latestRiskScore >= 75) {
      return 'I am concerned about you. Please reach out to your therapist 💙';
    }

    if (checkedInToday && latestRiskScore != null && latestRiskScore >= 50) {
      return 'I see today is a bit tough. I am here if you need me 💙';
    }

    if (checkedInToday && latestRiskScore != null && latestRiskScore < 50) {
      return 'Great job checking in today! You are doing well 🌟';
    }

    return 'I am here for you today 💙';
  }

  void _openCheckIn() {
    setState(() {
      _currentIndex = 1;
    });
  }

  void _openMyTwinTab() {
    setState(() {
      _currentIndex = 2;
    });
  }

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
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

  Widget _buildGreetingCard(Map<String, dynamic>? userData) {
    final name = _toStringOrNull(userData?['name']) ?? 'there';
    final greeting = _timeGreeting();
    final lastCheckInDate = _toDateTime(userData?['lastCheckInDate']);
    final latestRiskScore = _toDouble(userData?['latestRiskScore']);

    return AppCard(
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
            _allyMessage(
              patientName: name,
              lastCheckInDate: lastCheckInDate,
              latestRiskScore: latestRiskScore,
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
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
          return const AppCard(child: Center(child: CircularProgressIndicator()));
        }

        final userData = userSnapshot.data?.data();
        final riskScore = _toDouble(userData?['latestRiskScore']);
        if (riskScore == null) {
          return AppCard(
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

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Risk Score',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${normalizedRisk.toStringAsFixed(0)}% $riskLevelText ${riskBand.emoji}',
                style: TextStyle(
                  color: riskBand.color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                riskBand.label,
                style: TextStyle(
                  color: riskBand.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _dailyLogsStream(patientId),
                builder: (context, trendSnapshot) {
                  if (trendSnapshot.connectionState == ConnectionState.waiting &&
                      !trendSnapshot.hasData) {
                    return Text(
                      'Loading trend...',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                    );
                  }

                  final docs = trendSnapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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
                    '${_trendText(latestRisk, previousRisk)} vs yesterday',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
            return const AppCard(child: Center(child: CircularProgressIndicator()));
          }

          if (snapshot.hasError) {
            return AppCard(
              child: Text(
                _streakText(0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
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

    final progress =
        ((streak.toDouble() / 7.0) * 100.0).clamp(0.0, 100.0).toDouble();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _streakText(streak),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress / 100.0,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              color: AppTheme.primaryIndigo,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$progress% of your 7-day goal',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChartCard(String patientId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _dailyLogsStream(patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const EmptyState(message: 'Loading chart data...');
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return const EmptyState(message: 'Could not load chart data.');
        }

        final docs = snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final sortedDocs = docs.toList()
          ..sort((a, b) {
            final aTime = _toDateTime(a.data()['timestamp']);
            final bTime = _toDateTime(b.data()['timestamp']);
            if (aTime == null || bTime == null) return 0;
            return aTime.compareTo(bTime);
          });

        if (sortedDocs.isEmpty) {
          return EmptyState(
            message: 'Complete check-ins to see your chart',
            emoji: '📊',
            action: TextButton(
              onPressed: _openCheckIn,
              child: const Text('Start Check-in →'),
            ),
          );
        }

        final logs = sortedDocs.length > 7
            ? sortedDocs.sublist(sortedDocs.length - 7)
            : sortedDocs;

        final points = logs.map((d) {
          final data = d.data();
          return TwinChartPoint(
            timestamp: _toDateTime(data['timestamp']) ?? DateTime.now(),
            mood: _toDouble(data['moodScore']),
            sleep: _toDouble(data['sleepScore']),
            energy: _toDouble(data['energyScore']),
            risk: _toDouble(data['riskScore']),
          );
        }).toList();

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TwinTrendChart(points: points),
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
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _openMyTwinTab,
                  child: const Text('View Full Twin →'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStartMyDayCard(String patientId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _dailyLogsStream(patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const EmptyState(message: 'Loading today\'s check-in status...');
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return const EmptyState(message: 'Could not verify today\'s check-in.');
        }

        final docs = snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final checkedInToday = docs.any((doc) {
          final ts = _toDateTime(doc.data()['timestamp']);
          if (ts == null) return false;
          return _isSameDay(ts.toLocal(), DateTime.now().toLocal());
        });

        return AppCard(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: 64,
            child: ElevatedButton(
              onPressed: _openCheckIn,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    checkedInToday ? AppTheme.safeGreen.withValues(alpha: 0.25) : AppTheme.primaryIndigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 64),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                checkedInToday ? 'View Today\'s Check-in ✓' : '🌅 Start My Day',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
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
        child: AppCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          onTap: onTap,
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(
          emoji: '🤖',
          label: 'Talk to Ally',
          onTap: _openAllyChat,
        ),
        const SizedBox(width: 10),
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
        const SizedBox(width: 10),
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

  Widget _buildAppointmentReminder(String patientId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _todayAppointmentStream(patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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
        if (scheduledAt == null ||
            !_isSameDay(scheduledAt.toLocal(), DateTime.now().toLocal())) {
          return const SizedBox.shrink();
        }

        final therapistName =
            _toStringOrNull(data['therapistName']) ?? 'Therapist name unavailable';
        final timeText = DateFormat('hh:mm a').format(scheduledAt);

        return AppCard(
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
          return const Center(
            child: Text(
              'Loading home data...',
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        if (userSnapshot.hasError && !userSnapshot.hasData) {
          return const Center(
            child: Text(
              'Could not load home data.',
              style: TextStyle(color: Colors.white),
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
              _buildStartMyDayCard(patientId),
              const SizedBox(height: 18),
              const SectionHeader(title: 'Today at a Glance', emoji: '📊'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildRiskCard(patientId)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStreakCard(patientId, userData)),
                ],
              ),
              const SizedBox(height: 18),
              const SectionHeader(title: 'My Twin', emoji: '🧬'),
              _buildMiniChartCard(patientId),
              const SizedBox(height: 18),
              const SectionHeader(title: 'Quick Actions', emoji: '⚡'),
              _buildQuickActions(),
              const SizedBox(height: 18),
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
      DailyCheckInScreen(embedded: true, onNavigateTab: _switchTab),
      const MyTwinScreen(),
      const VoiceJournalScreen(),
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
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
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
          NavigationDestination(
            icon: Icon(Icons.edit_calendar_outlined),
            label: 'Check-in',
          ),
          NavigationDestination(icon: Icon(Icons.auto_graph), label: 'My Twin'),
          NavigationDestination(icon: Icon(Icons.mic_none), label: 'Journal'),
          NavigationDestination(
            icon: Icon(Icons.privacy_tip_outlined),
            label: 'Privacy',
          ),
        ],
      ),
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
