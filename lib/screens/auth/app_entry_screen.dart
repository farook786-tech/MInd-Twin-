import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/role_service.dart';
import '../../services/wearable_sync_service.dart';
import '../patient/patient_home_screen.dart';
import '../therapist/therapist_dashboard_screen.dart';
import 'complete_registration_screen.dart';
import 'patient_auth_screen.dart';
import 'role_selection_screen.dart';
import 'therapist_auth_screen.dart';
import 'therapist_pending_screen.dart';

/// Single routing gate for the whole app. Every login, registration,
/// approval and logout funnels back here; it decides the destination
/// ONLY from the Firebase Auth custom claim `role` and the compile-time
/// APP_MODE. A role that this build does not serve is signed out.
class AppEntryScreen extends StatefulWidget {
  /// Optional message shown on the login screen (e.g. after a forced sign-out).
  final String? notice;

  const AppEntryScreen({super.key, this.notice});

  /// Clears the navigation stack and re-runs the routing decision.
  static void restart(BuildContext context, {String? notice}) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AppEntryScreen(notice: notice)),
      (_) => false,
    );
  }

  @override
  State<AppEntryScreen> createState() => _AppEntryScreenState();
}

class _AppEntryScreenState extends State<AppEntryScreen> {
  Widget? _destination;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _notice = widget.notice;
    _resolve();
  }

  Widget _loginScreen() {
    if (AppConfig.isPatientOnlyMode) return PatientAuthScreen(initialMessage: _notice);
    if (AppConfig.isTherapistOnlyMode) return TherapistAuthScreen(initialMessage: _notice);
    return const RoleSelectionScreen(); // debug-only unified mode
  }

  Future<void> _resolve() async {
    final auth = AuthService();
    Widget dest;
    if (!auth.isAuthenticated) {
      dest = _loginScreen();
    } else {
      final role = await auth.refreshRole();
      final decision = RoleService.instance.destinationFor(role);
      switch (decision) {
        case RoleDestination.patientHome:
          if (auth.getCurrentUser() == null) await auth.refreshProfile();
          unawaited(WearableSyncService().startForCurrentPatient());
          dest = const PatientHomeScreen();
          break;
        case RoleDestination.therapistHome:
          if (auth.getCurrentUser() == null) await auth.refreshProfile();
          dest = const TherapistDashboardScreen();
          break;
        case RoleDestination.therapistPending:
          dest = const TherapistPendingScreen();
          break;
        case RoleDestination.completeRegistration:
          dest = const CompleteRegistrationScreen();
          break;
        case RoleDestination.wrongApp:
          _notice = RoleService.instance.wrongAppMessage(role);
          await auth.logout();
          dest = _loginScreen();
          break;
      }
    }
    if (!mounted) return;
    setState(() => _destination = dest);
  }

  @override
  Widget build(BuildContext context) {
    final d = _destination;
    if (d != null) return d;
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
