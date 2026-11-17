import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/patient/patient_appointments_screen.dart';
import '../screens/therapist/appointments_screen.dart';
import '../screens/therapist/real_time_alerts_center_screen.dart';
import 'auth_service.dart';

/// Navigator key the root [MaterialApp] MUST use (`navigatorKey:
/// appNavigatorKey`) so notification taps can open screens from anywhere.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Routes notification taps (FCM `onMessageOpenedApp`, `getInitialMessage`
/// and local-notification taps) to the right screen.
///
/// Push data payload contract (docs/DATA_MODEL.md):
///   `{type: 'chat', chatId, senderId}`
///   `{type: 'crisis', eventId, patientId}`
///   `{type: 'appointment', appointmentId}`
///
/// Navigation only ever happens in response to a user tap, never because a
/// message merely arrived.
class NotificationRouter {
  NotificationRouter._();
  static final NotificationRouter instance = NotificationRouter._();

  /// The key used for navigation. Defaults to [appNavigatorKey]; may be
  /// replaced (e.g. via `FCMService.navigatorKey = ...`) as long as the same
  /// key is handed to the MaterialApp.
  static GlobalKey<NavigatorState> navigatorKey = appNavigatorKey;

  /// chatId of the conversation currently visible on screen (set by
  /// ChatScreen). Foreground pushes for this chat are not shown and taps for
  /// it do not push a duplicate screen.
  static String? activeChatId;

  static const String alertsRouteName = '/notification/alerts';
  static const String appointmentsRouteName = '/notification/appointments';
  static String chatRouteName(String chatId) => '/notification/chat/$chatId';

  Map<String, dynamic>? _pending;
  Timer? _retryTimer;
  int _retryCount = 0;
  StreamSubscription<User?>? _authWaitSub;

  /// Handle a tapped notification's data payload. Safe to call before the
  /// navigator exists or before the user has signed in: the request is kept
  /// and executed as soon as both are available (only the latest is kept).
  void handle(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    _pending = Map<String, dynamic>.from(data);
    _retryCount = 0;
    _tryFlush();
  }

  void _tryFlush() {
    _retryTimer?.cancel();
    final data = _pending;
    if (data == null) return;

    if (FirebaseAuth.instance.currentUser == null) {
      // Wait for sign-in; give the auth flow time to replace its routes
      // with the home screen before pushing on top of it.
      _authWaitSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user == null) return;
        _authWaitSub?.cancel();
        _authWaitSub = null;
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(milliseconds: 1500), _tryFlush);
      });
      return;
    }

    final nav = navigatorKey.currentState;
    if (nav == null) {
      // Cold start: the first frame has not been built yet.
      if (_retryCount++ < 50) {
        _retryTimer = Timer(const Duration(milliseconds: 200), _tryFlush);
      } else {
        debugPrint('NotificationRouter: navigator never became available; '
            'is MaterialApp.navigatorKey set to appNavigatorKey?');
        _pending = null;
      }
      return;
    }

    _pending = null;
    _route(nav, data);
  }

  bool get _isTherapistApp {
    if (AppConfig.isTherapistOnlyMode) return true;
    if (AppConfig.isPatientOnlyMode) return false;
    return AuthService().currentRole == 'therapist';
  }

  String _normalizedType(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();
    if (type.isNotEmpty) return type;
    // Legacy backend payloads.
    if (data['notificationType'] == 'chat_message') return 'chat';
    return '';
  }

  void _route(NavigatorState nav, Map<String, dynamic> data) {
    switch (_normalizedType(data)) {
      case 'chat':
        _openChat(nav, data);
        break;
      case 'crisis':
      case 'sos':
        if (!_isTherapistApp) return;
        _pushUnlessOnTop(
          nav,
          alertsRouteName,
          (_) => const RealTimeAlertsCenterScreen(),
        );
        break;
      case 'appointment':
        _pushUnlessOnTop(
          nav,
          appointmentsRouteName,
          (_) => _isTherapistApp
              ? const AppointmentsScreen()
              : const PatientAppointmentsScreen(),
        );
        break;
      default:
        debugPrint('NotificationRouter: unhandled payload type ${data['type']}');
    }
  }

  void _openChat(NavigatorState nav, Map<String, dynamic> data) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    var chatId = (data['chatId'] ?? '').toString();
    var otherId = (data['senderId'] ?? '').toString();
    if (otherId.isEmpty || otherId == myUid) {
      // Derive the other participant from the canonical chat id.
      final parts = chatId.split('__');
      otherId = parts.firstWhere((p) => p.isNotEmpty && p != myUid,
          orElse: () => '');
    }
    if (otherId.isEmpty) return;
    if (chatId.isEmpty) {
      final ids = [myUid, otherId]..sort();
      chatId = ids.join('__');
    }

    if (activeChatId == chatId) return; // already looking at it

    _pushUnlessOnTop(
      nav,
      chatRouteName(chatId),
      (_) => ChatScreen(
        otherUserId: otherId,
        otherUserName: (data['senderName'] ?? '').toString(),
        isTherapist: _isTherapistApp,
      ),
    );
  }

  void _pushUnlessOnTop(
    NavigatorState nav,
    String routeName,
    WidgetBuilder builder,
  ) {
    if (_topRouteName(nav) == routeName) return;
    nav.push(MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName),
      builder: builder,
    ));
  }

  String? _topRouteName(NavigatorState nav) {
    String? name;
    // popUntil with an always-true predicate pops nothing; it just lets us
    // inspect the current top route.
    nav.popUntil((route) {
      name = route.settings.name;
      return true;
    });
    return name;
  }
}
