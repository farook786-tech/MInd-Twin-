import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'patient_crisis_reporter.dart';

/// Outcome of an SOS from the phone, for the emergency help sheet.
@immutable
class SosOutcome {
  /// The server acknowledged the `crisis_events` write.
  final bool delivered;
  final CrisisReportStatus status;
  final String message;

  const SosOutcome({required this.delivered, required this.status, required this.message});
}

/// Patient SOS from the phone (home SOS button, AI-chat "Connect therapist").
///
/// Writes `crisis_events` {eventType 'sos', severity 'critical'} via
/// [PatientCrisisReporter]. Waits at most ~8 s for the server; when offline or
/// slow the write stays in Firestore's persistent queue and is delivered
/// automatically on reconnect — the caller then offers the trusted contact
/// (SMS, never sent silently) and Tele-MANAS 14416.
class SosReporter {
  SosReporter._();

  static const Duration serverWait = Duration(seconds: 8);

  static Future<bool> _looksOffline() async {
    try {
      final r = await Connectivity().checkConnectivity().timeout(const Duration(seconds: 1));
      return r == ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }

  static Future<SosOutcome> sendFromPhone({
    required String source,
    String title = 'SOS alert',
    String message = 'The patient pressed the SOS button and needs urgent help.',
  }) async {
    final offline = await _looksOffline();
    CrisisReportStatus status;
    try {
      status = await PatientCrisisReporter.report(
        eventType: 'sos',
        severity: 'critical',
        title: title,
        message: message,
        source: source,
        // Offline: don't make the patient wait; the write is queued at once.
        timeout: offline ? const Duration(seconds: 1) : serverWait,
      ).timeout(serverWait + const Duration(seconds: 2), onTimeout: () => CrisisReportStatus.queued);
    } catch (e) {
      debugPrint('[SOS] report failed: $e');
      status = CrisisReportStatus.failed;
    }
    return SosOutcome(
      delivered: status == CrisisReportStatus.delivered,
      status: status,
      message: describe(status, offline: offline),
    );
  }

  static String describe(CrisisReportStatus status, {bool offline = false}) {
    switch (status) {
      case CrisisReportStatus.delivered:
        return 'Your therapist has been alerted.';
      case CrisisReportStatus.queued:
        return '${offline ? 'You are offline' : 'Your connection is slow'}. Your SOS is saved on this '
            'phone and will be sent to your therapist automatically as soon as you are back online. '
            'Please reach someone now.';
      case CrisisReportStatus.noTherapist:
      case CrisisReportStatus.failed:
        return PatientCrisisReporter.describe(status);
    }
  }
}
