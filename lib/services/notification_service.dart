// Notification Service - Simplified version
// Using FCM for push notifications instead of flutter_local_notifications
class NotificationService {
  static Future<void> initialize() async {
    print('NotificationService initialized (notifications via FCM)');
  }

  static Future<void> showSosAlert({
    required String patientName,
    required String reason,
  }) async {
    print('SOS Alert: $patientName - $reason');
    // Notifications are handled by FCM
  }

  static Future<void> showNewMessage({
    required String senderName,
    required String preview,
  }) async {
    print('New Message from $senderName: $preview');
    // Notifications are handled by FCM
  }
}
