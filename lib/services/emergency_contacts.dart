import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// One dialable emergency / crisis number.
@immutable
class EmergencyNumber {
  /// Human-readable name shown as the title.
  final String name;

  /// What the line is for, shown as the subtitle.
  final String description;

  /// Number as displayed (may contain dashes / spaces).
  final String display;

  /// Digits passed to `tel:`.
  final String dial;

  const EmergencyNumber({
    required this.name,
    required this.description,
    required this.display,
    required this.dial,
  });
}

/// Emergency and crisis numbers. MindTwin's users are in INDIA, so Indian
/// services are primary everywhere; other countries are listed only in a
/// secondary "Outside India" section.
///
/// Verified 2026-11-17:
///  * Tele-MANAS (Ministry of Health & Family Welfare, National Tele Mental
///    Health Programme): 14416 or 1-800-891-4416, free, 24x7, multilingual.
///  * 112: India's single Emergency Response Support System number
///    (police / fire / ambulance).
///  * KIRAN (1800-599-0019, Ministry of Social Justice) has been MERGED into
///    Tele-MANAS (calls diverted, then phased out), so it is deliberately NOT
///    listed; Tele-MANAS is the national line. Re-verify before the pilot.
class EmergencyContacts {
  EmergencyContacts._();

  static const EmergencyNumber teleManas = EmergencyNumber(
    name: 'Tele-MANAS',
    description: 'National mental health helpline (Govt. of India) · free · 24x7 · many languages',
    display: '14416',
    dial: '14416',
  );

  static const EmergencyNumber teleManasTollFree = EmergencyNumber(
    name: 'Tele-MANAS (toll-free)',
    description: 'Same helpline, alternative number',
    display: '1-800-891-4416',
    dial: '18008914416',
  );

  static const EmergencyNumber emergency112 = EmergencyNumber(
    name: 'Emergency 112',
    description: 'Police / ambulance / fire — if you are in immediate danger',
    display: '112',
    dial: '112',
  );

  /// India — shown first, in this order.
  static const List<EmergencyNumber> india = [teleManas, emergency112, teleManasTollFree];

  /// Secondary section for patients who are travelling.
  static const List<EmergencyNumber> outsideIndia = [
    EmergencyNumber(
      name: 'Suicide & Crisis Lifeline (US / Canada)',
      description: 'Call or text',
      display: '988',
      dial: '988',
    ),
    EmergencyNumber(
      name: 'Emergency (US / Canada)',
      description: 'Police / ambulance / fire',
      display: '911',
      dial: '911',
    ),
    EmergencyNumber(
      name: 'Samaritans (UK / Ireland)',
      description: 'Free, 24x7',
      display: '116 123',
      dial: '116123',
    ),
    EmergencyNumber(
      name: 'Emergency (UK)',
      description: 'Police / ambulance / fire',
      display: '999',
      dial: '999',
    ),
    EmergencyNumber(
      name: 'Emergency (EU and many other countries)',
      description: 'Police / ambulance / fire',
      display: '112',
      dial: '112',
    ),
  ];

  /// Pre-filled text for "Text my trusted contact". Never sent silently: the
  /// SMS app opens and the patient presses send.
  static const String trustedContactSmsBody = "I'm not okay and need help. Please call me.";

  /// Opens the dialer with [number]. Returns false if no dialer could open.
  static Future<bool> call(String number) async {
    final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return false;
    try {
      return await launchUrl(Uri(scheme: 'tel', path: digits));
    } catch (e) {
      debugPrint('[EmergencyContacts] tel launch failed: $e');
      return false;
    }
  }

  /// Opens the SMS app with [phone] and [body] pre-filled. The patient must
  /// press send themselves. Returns false if no SMS app could open.
  static Future<bool> openSms(String phone, {String body = trustedContactSmsBody}) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return false;
    // Built by hand: Uri(queryParameters:) encodes spaces as '+', which many
    // Android SMS apps show literally.
    final uri = Uri.parse('sms:$digits?body=${Uri.encodeComponent(body)}');
    try {
      return await launchUrl(uri);
    } catch (e) {
      debugPrint('[EmergencyContacts] sms launch failed: $e');
      return false;
    }
  }
}
