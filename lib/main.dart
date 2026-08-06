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
        return const TherapistAuthScreen();
      }
      return const PatientHomeScreen();
    }

    if (authService.currentRole == 'therapist') {
      if (!AppConfig.therapistAccessEnabled) {
        return const PatientAuthScreen();
      }
      return const TherapistDashboardScreen();
    }

    // Fallback: No valid role found, return to auth
    return AppConfig.patientAccessEnabled
        ? const PatientAuthScreen()
        : const TherapistAuthScreen();
  }
}

