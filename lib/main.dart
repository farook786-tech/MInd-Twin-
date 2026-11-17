import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/auth/app_entry_screen.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/fcm_service.dart';
import 'services/notification_router.dart';
import 'services/notification_service.dart';
import 'services/push_token_service.dart';
import 'services/token_service.dart';
import 'services/wearable_sync_service.dart';

/// Startup order (docs/DATA_MODEL.md):
///  1. Firebase.initializeApp
///  2. FCMService().initialize()  (idempotent; also starts PushTokenService,
///     which registers/refreshes `fcm_tokens` on every auth change)
///  3. TokenService (backend JWT) + AuthService (role claim + profile)
///  4. AppEntryScreen routes by claim; the patient app starts
///     WearableSyncService after login. Logout unregisters the push token and
///     stops wearable sync before FirebaseAuth.signOut().
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.logStartupDiagnostics();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
  } catch (e) {
    // Without Firebase there is no auth, no real-time data and no alerts.
    debugPrint('Firebase initialization FAILED: $e');
    // e.g. 'duplicate-app' after a hot restart: the default app exists.
    firebaseReady = Firebase.apps.isNotEmpty;
  }

  if (!firebaseReady) {
    runApp(const _FatalStartupApp(
      message: 'MindTwin could not start its secure connection. '
          'Please check your internet connection and restart the app.\n\n'
          'If you are in crisis, call your local emergency number now.',
    ));
    return;
  }

  // Local notifications (channels) before FCM so foreground pushes can show.
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Notification service not available: $e');
  }

  if (!kIsWeb) {
    unawaited(FCMService().initialize().catchError((Object e) {
      debugPrint('FCM not available: $e');
    }));
    // FCMService already starts this; calling with the explicit app name is
    // idempotent and pins the `app` field for this build.
    PushTokenService.instance.start(app: AppConfig.isTherapistOnlyMode ? 'therapist' : 'patient');
  }

  try {
    await TokenService().init();
  } catch (e) {
    debugPrint('TokenService init failed: $e');
  }
  await AuthService().init();
  await ThemeController.instance.load();

  if (!kIsWeb) {
    try {
      await DatabaseService().database;
    } catch (e) {
      debugPrint('Database initialization skipped: $e');
    }
  }

  // Patient app: resume wearable sync for a persisted session. The service
  // itself verifies the `patient` claim and APP_MODE.
  if (!kIsWeb && FirebaseAuth.instance.currentUser != null && AppConfig.patientAccessEnabled) {
    unawaited(WearableSyncService().startForCurrentPatient());
  }

  runApp(const MindTwinApp());
}

class MindTwinApp extends StatefulWidget {
  const MindTwinApp({super.key});

  @override
  State<MindTwinApp> createState() => _MindTwinAppState();
}

class _MindTwinAppState extends State<MindTwinApp> {
  StreamSubscription<User?>? _authSub;
  String? _lastUid;

  @override
  void initState() {
    super.initState();
    _lastUid = FirebaseAuth.instance.currentUser?.uid;
    // Safety net: if the session ends without going through AuthService.logout
    // (token revoked, account disabled, deleted elsewhere), stop wearable
    // sync and return to the login gate so no screen keeps showing data.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final wasSignedIn = _lastUid != null;
      _lastUid = user?.uid;
      if (user != null || !wasSignedIn) return;
      if (AuthService().isLoggingOut) return; // caller navigates itself
      unawaited(WearableSyncService().stop());
      final nav = appNavigatorKey.currentState;
      nav?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const AppEntryScreen(notice: 'You have been signed out. Please sign in again.'),
        ),
        (_) => false,
      );
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) => MaterialApp(
        title: AppConfig.isTherapistOnlyMode ? 'MindTwin Therapist' : 'MindTwin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        navigatorKey: appNavigatorKey,
        builder: (context, child) => ThemePaletteScope(child: child ?? const SizedBox.shrink()),
        // Every named entry point goes through the claim-based gate; there are
        // deliberately no direct '/patient' or '/therapist' routes.
        routes: <String, WidgetBuilder>{
          '/auth': (_) => const AppEntryScreen(),
        },
        home: const AppEntryScreen(),
      ),
    );
  }
}

class _FatalStartupApp extends StatelessWidget {
  final String message;
  const _FatalStartupApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) => ThemePaletteScope(child: child ?? const SizedBox.shrink()),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
