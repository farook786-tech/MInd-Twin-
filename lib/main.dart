import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/auth/patient_auth_screen.dart';
import 'screens/auth/therapist_auth_screen.dart';
import 'screens/patient/patient_home_screen.dart';
import 'screens/therapist/therapist_dashboard_screen.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'services/fcm_service.dart';
import 'services/token_service.dart';
import 'services/wearable_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first because AuthService and wearable sync depend on Firebase instances.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print('Firebase initialization skipped: $e');
  }

  // Initialize services
  final authService = AuthService();
  await authService.init();

  // Initialize wearable bridge after Firebase/Auth are ready.
  await WearableSyncService().initialize();
  
  // Initialize database only for non-web platforms
  if (!kIsWeb) {
    try {
      final dbService = DatabaseService();
      await dbService.database;
    } catch (e) {
      print('Database initialization skipped: $e');
    }
  }

  // Initialize notification service (skip on web if not supported)
  try {
    await NotificationService.initialize();
  } catch (e) {
    print('Notification service not available: $e');
  }
  
  // Initialize token service for JWT auth
  final tokenService = TokenService();
  await tokenService.init();
  
  // Initialize FCM for push notifications (non-blocking, gracefully fails if not configured)
  if (!kIsWeb) {
    FCMService.navigatorKey = GlobalKey<NavigatorState>();
    FCMService().initialize().catchError((e) {
      print('FCM not available: $e');
    });
  }
  
  runApp(const MindTwinApp());
}

class MindTwinApp extends StatelessWidget {
  const MindTwinApp({super.key});

  @override
  Widget build(BuildContext context) {
    final routes = <String, WidgetBuilder>{
      '/auth': (context) => const RoleSelectionScreen(),
    };

    if (AppConfig.patientAccessEnabled) {
      routes['/patient-auth'] = (context) => const PatientAuthScreen();
      routes['/patient'] = (context) => const PatientHomeScreen();
    }

    if (AppConfig.therapistAccessEnabled) {
      routes['/therapist-auth'] = (context) => const TherapistAuthScreen();
      routes['/therapist'] = (context) => const TherapistDashboardScreen();
    }

    return MaterialApp(
      title: 'MindTwin - AI Digital Twin Mental Health',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkMedicalTheme,
      navigatorKey: FCMService.navigatorKey,
      routes: routes,
      home: const AppEntryScreen(),
    );
  }
}

class AppEntryScreen extends StatelessWidget {
  const AppEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    if (!authService.isAuthenticated) {
      if (AppConfig.isPatientOnlyMode) {
        return const PatientAuthScreen();
      }
      if (AppConfig.isTherapistOnlyMode) {
        return const TherapistAuthScreen();
      }
      return const RoleSelectionScreen();
    }

    if (authService.currentRole == 'patient') {
      if (!AppConfig.patientAccessEnabled) {
        return const AppModeMismatchScreen(currentRole: 'patient');
      }
      return const PatientHomeScreen();
    }

    if (authService.currentRole == 'therapist') {
      if (!AppConfig.therapistAccessEnabled) {
        return const AppModeMismatchScreen(currentRole: 'therapist');
      }
      return const TherapistDashboardScreen();
    }

    // Fallback: No valid role found, return to auth
    return AppConfig.patientAccessEnabled
        ? const PatientAuthScreen()
        : const TherapistAuthScreen();
  }
}

/// Shown when the authenticated user's role is not included in this build's
/// APP_MODE. Previously the app bounced them to the other role's login screen
/// forever; now they get a clear explanation and a way to sign out.
class AppModeMismatchScreen extends StatelessWidget {
  final String currentRole;

  const AppModeMismatchScreen({super.key, required this.currentRole});

  Future<void> _signOut(BuildContext context) async {
    await AuthService().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final disabledRole = currentRole == 'patient' ? 'therapist' : 'patient';
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                '${currentRole[0].toUpperCase()}${currentRole.substring(1)} '
                'access is disabled in this build',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This app was built in ${AppConfig.modeLabel} mode '
                '(--dart-define=APP_MODE=${AppConfig.modeLabel}), which '
                'intentionally hides $disabledRole access. Sign out to '
                'switch roles.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _signOut(context),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

