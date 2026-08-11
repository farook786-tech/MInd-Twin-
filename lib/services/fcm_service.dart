import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_service.dart';
import 'auth_service.dart';
import '../screens/chat/chat_screen.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  static bool _initialized = false;
  FirebaseMessaging? _messaging;

  /// Set from the root MaterialApp so chat notifications can deep-link to
  /// the conversation screen.
  static GlobalKey<NavigatorState>? navigatorKey;
  
  factory FCMService() {
    return _instance;
  }

  FCMService._internal();

  /// Initialize FCM
  Future<void> initialize() async {
    try {
      // Initialize Firebase if not already done
      if (Firebase.apps.isEmpty) {
        // Note: In a real app, set up google-services.json and google-info.plist
        // For now, this will gracefully fail and fall back to local notifications
        print('Firebase not configured - using local notifications only');
        return;
      }

      // Only access FirebaseMessaging after Firebase is initialized
      _messaging = FirebaseMessaging.instance;

      // Request notification permissions
      final settings = await _messaging!.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        provisional: false,
        sound: true,
      );

      print('User granted notification permission: ${settings.authorizationStatus}');

      // Get FCM token
      final token = await _messaging!.getToken();
      print('FCM Token: $token');

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Got a message whilst in the foreground!');
        _handleRemoteMessage(message);
      });

      // Handle app in background, notification tapped to open
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleRemoteMessage(message);
      });

      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle message click on terminated app
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        _handleRemoteMessage(initialMessage);
      }

      _initialized = true;
    } catch (e) {
      print('FCM initialization error (falling back to local notifications): $e');
      // Graceful fallback - local notifications will still work
    }
  }

  /// Get FCM token for backend registration
  Future<String?> getToken() async {
    try {
      if (!_initialized || _messaging == null) return null;
      return await _messaging!.getToken();
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  /// Subscribe to topic for group messages
  Future<void> subscribeToTopic(String topic) async {
    try {
      if (!_initialized || _messaging == null) return;
      await _messaging!.subscribeToTopic(topic);
      print('Subscribed to topic: $topic');
    } catch (e) {
      print('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      if (!_initialized || _messaging == null) return;
      await _messaging!.unsubscribeFromTopic(topic);
      print('Unsubscribed from topic: $topic');
    } catch (e) {
      print('Error unsubscribing from topic: $e');
    }
  }

  /// Handle incoming remote message
  void _handleRemoteMessage(RemoteMessage message) {
    print('Message data: ${message.data}');

    // Chat push notifications deep-link to the conversation.
    if (message.data['notificationType'] == 'chat_message') {
      _openChat(message.data);
      return;
    }

    if (message.notification != null) {
      print('Message also contained a notification: ${message.notification}');

      final title = message.notification!.title;
      final body = message.notification!.body;
      final data = message.data;

      // Route to appropriate handler
      if (data['type'] == 'sos') {
        NotificationService.showSosAlert(
          patientName: data['patientName'] ?? 'Patient',
          reason: data['reason'] ?? 'SOS Alert',
        );
      } else if (data['type'] == 'message') {
        NotificationService.showNewMessage(
          senderName: data['senderName'] ?? 'User',
          preview: body ?? 'New message',
        );
      } else {
        // Generic notification
        _showCustomNotification(title ?? 'Notification', body ?? '');
      }
    }
  }

  /// Deep-link a chat push into the matching conversation screen.
  void _openChat(Map<String, dynamic> data) {
    final otherUserId = data['senderId']?.toString();
    final otherUserName = data['senderName']?.toString() ?? 'Contact';
    if (otherUserId == null || otherUserId.isEmpty) return;

    // The sender is the other party; the recipient is the current user, so
    // the "isTherapist" flag is the inverse of the current user's role.
    final isTherapist = AuthService().currentRole != 'therapist';

    void navigate() {
      final nav = navigatorKey?.currentState;
      if (nav == null) return;
      nav.push(MaterialPageRoute(
        builder: (context) => ChatScreen(
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          isTherapist: isTherapist,
        ),
      ));
    }

    // The first frame may not exist yet when the app was launched from a
    // notification tap; defer until it does.
    WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
  }

  /// Show custom notification via local notifications
  Future<void> _showCustomNotification(String title, String body) async {
    // Fallback to local notifications
    print('Showing local notification: $title - $body');
  }
}

/// Background message handler (must be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
  // Handle background message
  if (message.notification != null) {
    print('Message notification: ${message.notification}');
  }
}
