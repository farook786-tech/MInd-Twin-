import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'notification_router.dart';
import 'notification_service.dart';
import 'push_token_service.dart';

/// Background / terminated-state handler. Must be a top-level function.
///
/// Pushes that carry a `notification` block are displayed by the OS itself
/// (on the Android channel chosen by the Cloud Function), so only data-only
/// pushes need a local notification here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) return;
  if (message.data.isEmpty) return;
  try {
    await NotificationService.initialize();
    await NotificationService.showForData(message.data);
  } catch (e) {
    debugPrint('Background push handling failed: $e');
  }
}

/// Firebase Cloud Messaging wiring. Pushes are sent by Cloud Functions
/// (docs/DATA_MODEL.md); this class only receives and displays them.
///
/// * Foreground message -> local notification (suppressed for the chat that
///   is currently open). Never navigates by itself.
/// * Notification tap (background, terminated, or local) -> navigation via
///   [NotificationRouter].
/// * Token registration is delegated to [PushTokenService], which reacts to
///   FirebaseAuth sign-in on its own.
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  Future<void>? _initFuture;
  bool _initialized = false;
  final List<StreamSubscription<RemoteMessage>> _subs = [];

  /// Navigator used for notification deep links. Prefer passing
  /// [appNavigatorKey] to MaterialApp; this setter remains so existing code
  /// assigning a key keeps working (the same key must go to MaterialApp).
  static GlobalKey<NavigatorState> get navigatorKey =>
      NotificationRouter.navigatorKey;
  static set navigatorKey(GlobalKey<NavigatorState>? key) {
    if (key != null) NotificationRouter.navigatorKey = key;
  }

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get isInitialized => _initialized;

  /// Idempotent; safe to call before or after AuthService.init(). Requires
  /// Firebase.initializeApp() to have completed.
  Future<void> initialize() {
    if (!isSupported) return Future.value();
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    if (Firebase.apps.isEmpty) {
      debugPrint('FCMService: Firebase not initialised; push disabled');
      _initFuture = null; // allow retry after Firebase.initializeApp
      return;
    }

    // Must be registered before any await so it is in place for the
    // background isolate as early as possible.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      await NotificationService.initialize();

      final messaging = FirebaseMessaging.instance;
      try {
        // On Android 13+ this triggers the POST_NOTIFICATIONS runtime prompt.
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        debugPrint(
            'Notification permission: ${settings.authorizationStatus.name}');
      } catch (e) {
        debugPrint('FCMService: permission request failed: $e');
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // We present foreground pushes ourselves via local notifications.
        await messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );
      }

      _subs.add(FirebaseMessaging.onMessage.listen(_onForegroundMessage));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => NotificationRouter.instance.handle(message.data),
      ));

      // Token registration follows FirebaseAuth state from here on.
      PushTokenService.instance.start();

      // App launched by tapping a push while terminated.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        NotificationRouter.instance.handle(initial.data);
      } else {
        // App launched by tapping one of our local notifications.
        final launch = await NotificationService.launchPayload();
        if (launch != null) NotificationRouter.instance.handle(launch);
      }

      _initialized = true;
    } catch (e) {
      debugPrint('FCMService initialization error: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final isChat = data['type'] == 'chat' ||
        data['notificationType'] == 'chat_message';
    if (isChat) {
      final chatId = data['chatId']?.toString();
      final active = NotificationRouter.activeChatId;
      if (active != null && chatId == active) return; // already on screen
    }
    await NotificationService.showForData(
      data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }

  /// Current FCM token (null when unsupported / unavailable).
  Future<String?> getToken() async {
    if (!isSupported || Firebase.apps.isEmpty) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (!isSupported || Firebase.apps.isEmpty) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
    } catch (e) {
      debugPrint('Error subscribing to topic: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (!isSupported || Firebase.apps.isEmpty) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
    } catch (e) {
      debugPrint('Error unsubscribing from topic: $e');
    }
  }
}
