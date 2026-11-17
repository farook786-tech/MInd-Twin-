import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_router.dart';

/// Local (on-device) notifications.
///
/// Used for: foreground pushes (FCM does not display those itself), data-only
/// pushes received in the background isolate, and locally generated alerts.
/// Android channels are created here and MUST match the ids the Cloud
/// Functions send to (docs/DATA_MODEL.md):
///   clinical_critical (max), chat_messages (high), appointments (default).
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static Future<bool>? _initFuture;

  static const String channelCritical = 'clinical_critical';
  static const String channelChat = 'chat_messages';
  static const String channelAppointments = 'appointments';

  static const AndroidNotificationChannel _criticalChannel =
      AndroidNotificationChannel(
    channelCritical,
    'Critical clinical alerts',
    description: 'Crisis and SOS alerts that need immediate attention',
    importance: Importance.max,
    enableVibration: true,
    playSound: true,
  );

  static const AndroidNotificationChannel _chatChannel =
      AndroidNotificationChannel(
    channelChat,
    'Messages',
    description: 'Messages between patients and their therapist',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _appointmentsChannel =
      AndroidNotificationChannel(
    channelAppointments,
    'Appointments',
    description: 'Appointment requests, confirmations and changes',
    importance: Importance.defaultImportance,
  );

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Idempotent. Creates the Android channels and registers the tap handler.
  /// Permission prompts are NOT triggered here; FCMService requests them via
  /// FirebaseMessaging.requestPermission (covers Android 13+
  /// POST_NOTIFICATIONS and iOS).
  static Future<bool> initialize() {
    if (!isSupported) return Future.value(false);
    return _initFuture ??= _initialize();
  }

  static Future<bool> _initialize() async {
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(_criticalChannel);
        await android.createNotificationChannel(_chatChannel);
        await android.createNotificationChannel(_appointmentsChannel);
      }
      return true;
    } catch (e) {
      debugPrint('NotificationService initialization failed: $e');
      _initFuture = null; // allow a later retry
      return false;
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    final data = decodePayload(response.payload);
    if (data != null) NotificationRouter.instance.handle(data);
  }

  /// Payload of the local notification that launched the app, if any.
  static Future<Map<String, dynamic>?> launchPayload() async {
    if (!await initialize()) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return decodePayload(details.notificationResponse?.payload);
    } catch (e) {
      debugPrint('NotificationService.launchPayload failed: $e');
      return null;
    }
  }

  static Map<String, dynamic>? decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static int _idFor(String key) => key.hashCode & 0x7fffffff;

  /// Show a notification for an FCM data payload (`type` = crisis | chat |
  /// appointment). [title]/[body] come from the push's notification block or
  /// its data `title`/`body`.
  static Future<void> showForData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) async {
    final payload = jsonEncode(data);
    final resolvedTitle = title ?? data['title']?.toString();
    final resolvedBody = body ?? data['body']?.toString();
    var type = (data['type'] ?? '').toString();
    if (type.isEmpty && data['notificationType'] == 'chat_message') {
      type = 'chat';
    }

    switch (type) {
      case 'crisis':
      case 'sos':
        await showCriticalAlert(
          key: 'crisis_${data['eventId'] ?? data['patientId'] ?? payload}',
          title: resolvedTitle ?? 'Critical patient alert',
          body: resolvedBody ?? 'A patient needs immediate attention.',
          payload: payload,
        );
        break;
      case 'chat':
        await showChatMessage(
          chatId: (data['chatId'] ?? data['senderId'] ?? '').toString(),
          title: resolvedTitle ??
              (data['senderName']?.toString() ?? 'New message'),
          body: resolvedBody ?? 'You have a new message',
          payload: payload,
        );
        break;
      case 'appointment':
        await _show(
          id: _idFor('appointment_${data['appointmentId'] ?? payload}'),
          channel: _appointmentsChannel,
          title: resolvedTitle ?? 'Appointment update',
          body: resolvedBody ?? 'An appointment was updated',
          payload: payload,
        );
        break;
      default:
        if (resolvedTitle == null && resolvedBody == null) return;
        await _show(
          id: _idFor(payload),
          channel: _appointmentsChannel,
          title: resolvedTitle ?? 'MindTwin',
          body: resolvedBody ?? '',
          payload: payload,
        );
    }
  }

  /// Max-importance, full-screen-capable alert on `clinical_critical`.
  static Future<void> showCriticalAlert({
    required String key,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!await initialize()) return;
    try {
      await _plugin.show(
        id: _idFor(key),
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _criticalChannel.id,
            _criticalChannel.name,
            channelDescription: _criticalChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            ticker: title,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentSound: true,
            presentList: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService.showCriticalAlert failed: $e');
    }
  }

  /// One notification per conversation (a newer message replaces the older
  /// one for the same chat).
  static Future<void> showChatMessage({
    required String chatId,
    required String title,
    required String body,
    String? payload,
  }) {
    return _show(
      id: _idFor('chat_$chatId'),
      channel: _chatChannel,
      title: title,
      body: body,
      payload: payload,
    );
  }

  /// Remove the notification for a conversation (e.g. when it is opened).
  static Future<void> cancelChat(String chatId) async {
    if (!await initialize()) return;
    try {
      await _plugin.cancel(id: _idFor('chat_$chatId'));
    } catch (_) {}
  }

  static Future<void> _show({
    required int id,
    required AndroidNotificationChannel channel,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!await initialize()) return;
    final high = channel.importance == Importance.high;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: high ? Priority.high : Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentSound: true,
            presentList: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService.show failed: $e');
    }
  }

  // ---- Backwards-compatible helpers -------------------------------------

  static Future<void> showSosAlert({
    required String patientName,
    required String reason,
  }) {
    return showCriticalAlert(
      key: 'sos_$patientName',
      title: 'SOS: $patientName',
      body: reason,
      payload: jsonEncode({'type': 'crisis'}),
    );
  }

  static Future<void> showNewMessage({
    required String senderName,
    required String preview,
  }) {
    return showChatMessage(
      chatId: 'sender_$senderName',
      title: senderName,
      body: preview,
    );
  }
}
