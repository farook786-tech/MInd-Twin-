import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import 'dashboard_tab.dart';
import 'patients_tab.dart';
import 'simulator_tab.dart';
import 'federated_tab.dart';
import 'message_inbox_screen.dart';
import 'treatment_response_dashboard.dart';
import 'engagement_monitoring_dashboard.dart';
import 'appointments_screen.dart';
import 'real_time_alerts_center_screen.dart';
import 'treatment_report_screen.dart';
import 'engagement_reminder_stats_screen.dart';
import '../shared/profile_screen.dart';

class TherapistDashboardScreen extends StatefulWidget {
  const TherapistDashboardScreen({super.key});

  @override
  State<TherapistDashboardScreen> createState() => _TherapistDashboardScreenState();
}

class _TherapistDashboardScreenState extends State<TherapistDashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _tabs = const [
    DashboardTab(),
    PatientsTab(),
    AppointmentsScreen(),
    SimulatorTab(),
    FederatedTab(),
  ];

  final List<NavigationRailDestination> _destinations = const [
    NavigationRailDestination(
      icon: Icon(Icons.dashboard),
      label: Text('Dashboard'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.people),
      label: Text('Patients'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.calendar_today),
      label: Text('Appointments'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.science),
      label: Text('Simulator'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.hub),
      label: Text('Network'),
    ),
  ];

  Future<void> _handleQuickAction(String action) async {
    switch (action) {
      case 'alerts':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const RealTimeAlertsCenterScreen(),
          ),
        );
        break;
      case 'reports':
        await _showPatientsForReports();
        break;
      case 'analytics':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const EngagementReminderStatsScreen(),
          ),
        );
        break;
      case 'profile':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProfileScreen()),
        );
        break;
      case 'logout':
        await _logout();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Therapist Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize_rounded),
            tooltip: 'Treatment Response Dashboard',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TreatmentResponseDashboard(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline_rounded),
            tooltip: 'Engagement Monitoring',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const EngagementMonitoringDashboard(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.mail),
            tooltip: 'Message Inbox',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MessageInboxScreen(),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            color: AppTheme.cardDark,
            onSelected: _handleQuickAction,
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'alerts',
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 10),
                    Text('Real-Time Alerts', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'reports',
                child: Row(
                  children: [
                    Icon(Icons.description_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 10),
                    Text('Clinical Reports', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'analytics',
                child: Row(
                  children: [
                    Icon(Icons.analytics_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 10),
                    Text('Reminder Analytics', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 10),
                    Text('Profile', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                    SizedBox(width: 10),
                    Text('Logout', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          // Navigation Rail for Web/Desktop
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            backgroundColor: AppTheme.cardDark,
            indicatorColor: AppTheme.primaryIndigo.withValues(alpha: 0.3),
            leading: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Icon(
                    Icons.psychology,
                    size: 40,
                    color: AppTheme.primaryIndigo,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'MindTwin',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryIndigo,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(color: Colors.white12, height: 12),
                  IconButton(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded),
                    tooltip: 'Logout',
                    color: Colors.redAccent,
                  ),
                  const Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            labelType: NavigationRailLabelType.all,
            destinations: _destinations,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main Content
          Expanded(
            child: _tabs[_selectedIndex],
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final authService = AuthService();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.riskRed,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await authService.logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/auth',
          (route) => false,
        );
      }
    }
  }

  Future<void> _showPatientsForReports() async {
    final db = DatabaseService();
    final patients = await db.getAllPatients();
    if (!mounted) return;

    if (patients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No patients found.')),
      );
      return;
    }

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Generate Report For'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: patients
                .map(
                  (patient) => ListTile(
                    title: Text(patient.name),
                    subtitle: Text('ID: ${patient.id}'),
                    onTap: () => Navigator.pop(context, patient),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TreatmentReportScreen(
            patientId: selected.id,
            patientName: selected.name,
          ),
        ),
      );
    }
  }
}
