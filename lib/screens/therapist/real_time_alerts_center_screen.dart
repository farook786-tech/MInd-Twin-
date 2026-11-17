import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../chat/chat_screen.dart';

/// Single therapist-facing alert inbox.
///
/// Every alert (patient SOS / check-in / chat crisis, server-raised high
/// risk, PHQ-9 severe, vital out of range) is a `crisis_events` document
/// (see docs/DATA_MODEL.md). The old `anomalies` section was removed: no
/// Cloud Function writes that collection, so it could only ever be empty.
class RealTimeAlertsCenterScreen extends StatelessWidget {
  const RealTimeAlertsCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final therapistId = AuthService().currentUserId;
    if (therapistId == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        appBar: AppBar(backgroundColor: AppTheme.cardDark, title: const Text('Real-Time Alerts Center')),
        body: const Center(
          child: Text('Please sign in as therapist.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final events = FirebaseFirestore.instance.collection('crisis_events');
    // Rules are not filters: every query is constrained to therapistId == me.
    final activeQuery = events
        .where('therapistId', isEqualTo: therapistId)
        .where('acknowledged', isEqualTo: false)
        .orderBy('timestamp', descending: true);
    final historyQuery = events
        .where('therapistId', isEqualTo: therapistId)
        .orderBy('timestamp', descending: true)
        .limit(100);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppTheme.cardDark,
          title: const Text('Real-Time Alerts Center'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AlertList(
              query: activeQuery,
              therapistId: therapistId,
              emptyTitle: 'All Clear',
              emptySubtitle: 'No unacknowledged alerts.',
            ),
            _AlertList(
              query: historyQuery,
              therapistId: therapistId,
              emptyTitle: 'No Alert History',
              emptySubtitle: 'Alerts for your patients will appear here.',
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertList extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  final String therapistId;
  final String emptyTitle;
  final String emptySubtitle;

  const _AlertList({
    required this.query,
    required this.therapistId,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryIndigo));
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return _EmptyState(title: emptyTitle, subtitle: emptySubtitle);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) => _AlertCard(
            docId: docs[index].id,
            alert: docs[index].data(),
            therapistId: therapistId,
          ),
        );
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> alert;
  final String therapistId;

  const _AlertCard({
    required this.docId,
    required this.alert,
    required this.therapistId,
  });

  @override
  Widget build(BuildContext context) {
    final patientId = _safeString(alert['patientId']);
    final patientName = _safeString(alert['patientName'], fallback: 'Unknown patient');
    final severity = _safeString(alert['severity'], fallback: 'high').toLowerCase();
    final eventType = _safeString(alert['eventType'], fallback: 'alert');
    final acknowledged = alert['acknowledged'] == true;
    final color = _severityColor(severity);
    final title = _safeString(alert['title'], fallback: _eventTypeLabel(eventType));
    final message = _safeString(alert['message'], fallback: _legacyMessage(alert));
    final vitalLine = _vitalLine(alert['vital']);
    final timestamp = _date(alert['timestamp']);
    final acknowledgedAt = _date(alert['acknowledgedAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: acknowledged ? 0.06 : 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: acknowledged ? color.withValues(alpha: 0.4) : color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_eventIcon(eventType), color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$patientName - $title',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              _SeverityChip(severity: severity, color: color),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(color: Colors.white70)),
          ],
          if (vitalLine != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    vitalLine,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            timestamp == null ? 'Time pending sync' : '${_relative(timestamp)} (${_absolute(timestamp)})',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
          ),
          if (acknowledged) ...[
            const SizedBox(height: 4),
            Text(
              acknowledgedAt == null ? 'Acknowledged' : 'Acknowledged ${_absolute(acknowledgedAt)}',
              style: const TextStyle(color: AppTheme.safeGreen, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (patientId.isNotEmpty)
                _btn(label: 'Call Patient', color: Colors.white, onTap: () => _callPatient(context, patientId)),
              if (patientId.isNotEmpty)
                _btn(
                  label: 'Send Message',
                  color: Colors.white,
                  onTap: () => _sendSafetyMessage(context, patientId, patientName),
                ),
              if (patientId.isNotEmpty)
                _btn(
                  label: 'Open Chat',
                  color: Colors.white,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        otherUserId: patientId,
                        otherUserName: patientName,
                        isTherapist: true,
                      ),
                    ),
                  ),
                ),
              if (!acknowledged)
                _btn(label: 'Acknowledge', color: AppTheme.safeGreen, onTap: () => _acknowledge(context)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledge(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Rules allow the therapist to change ONLY these three fields.
      await FirebaseFirestore.instance.collection('crisis_events').doc(docId).update({
        'acknowledged': true,
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'acknowledgedBy': therapistId,
      });
      messenger.showSnackBar(const SnackBar(content: Text('Alert acknowledged.')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.riskRed,
          content: Text('Could not acknowledge alert: ${_errorText(error)}'),
        ),
      );
    }
  }

  Future<void> _sendSafetyMessage(BuildContext context, String patientId, String patientName) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(
      text: 'I saw your alert and I am here with you now. Please reply when you can. '
          'If you are in immediate danger, call your local emergency number.',
    );
    final body = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: Text('Message $patientName', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (body == null || body.isEmpty) return;

    try {
      // resolvePeer verifies this patient is assigned to me (chats/{a__b}).
      final peer = await ChatService().resolvePeer(patientId);
      final sent = ChatService().sendMessage(peer: peer, text: body);
      // Do not await `committed` for the UI: offline it only completes once
      // the queued write reaches the server. Surface a late failure though.
      sent.committed.catchError((Object error) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.riskRed,
            content: Text('Message to $patientName failed to deliver: ${_errorText(error)}'),
          ),
        );
      });
      messenger.showSnackBar(const SnackBar(content: Text('Message sent (delivers as soon as online).')));
    } on ChatAccessException catch (error) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppTheme.riskRed, content: Text('Message NOT sent: ${error.message}')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.riskRed,
          content: Text('Message NOT sent: ${_errorText(error)}'),
        ),
      );
    }
  }

  Future<void> _callPatient(BuildContext context, String patientId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(patientId).get();
      final phone = _safeString(doc.data()?['phone']);
      if (phone.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No phone number on file for this patient. Use Send Message instead.')),
        );
        return;
      }
      final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
      final launched = await launchUrl(uri);
      if (!launched) {
        messenger.showSnackBar(SnackBar(content: Text('Could not start a call. Patient phone: $phone')));
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppTheme.riskRed, content: Text('Could not load phone: ${_errorText(error)}')),
      );
    }
  }
}

class _SeverityChip extends StatelessWidget {
  final String severity;
  final Color color;

  const _SeverityChip({required this.severity, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.safeGreen.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 56, color: AppTheme.safeGreen),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object? error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    // Never show "All clear" when the stream failed: that would hide crises.
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.riskRed),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.riskRed),
            const SizedBox(height: 10),
            const Text(
              'Alerts could not be loaded',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Alerts may exist that are not shown. ${_errorText(error)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _btn({
  required String label,
  required Color color,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

String _errorText(Object? error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Permission denied. Confirm your therapist account is approved, then sign out and back in.';
      case 'failed-precondition':
        return 'A required database index is missing or still building.';
      case 'unavailable':
        return 'Network unavailable. Retrying automatically.';
    }
    return error.message ?? error.code;
  }
  return error?.toString() ?? 'Unknown error';
}

String? _vitalLine(dynamic vital) {
  if (vital is! Map) return null;
  final type = _safeString(vital['type']);
  final value = vital['value'];
  if (type.isEmpty || value is! num) return null;
  final unit = _safeString(vital['unit']);
  final threshold = vital['threshold'];
  final label = switch (type) {
    'heart_rate' => 'Heart rate',
    'sleep' => 'Sleep',
    'steps' => 'Steps',
    _ => type,
  };
  final unitSuffix = unit.isEmpty ? '' : ' $unit';
  final thresholdText = threshold is num ? ' (threshold ${_fmtNum(threshold)}$unitSuffix)' : '';
  return '$label: ${_fmtNum(value)}$unitSuffix$thresholdText';
}

String _fmtNum(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);

/// Older crisis docs (before the contract) carried matchedPhrases/notes.
String _legacyMessage(Map<String, dynamic> alert) {
  final phrases = alert['matchedPhrases'];
  if (phrases is List && phrases.isNotEmpty) return phrases.map((e) => e.toString()).join(', ');
  return _safeString(alert['notes']);
}

String _eventTypeLabel(String type) {
  switch (type) {
    case 'sos':
      return 'SOS';
    case 'checkin_crisis':
      return 'Check-in crisis';
    case 'chat_crisis':
      return 'Crisis language in chat';
    case 'high_risk':
      return 'High risk score';
    case 'phq9_severe':
      return 'Severe PHQ-9';
    case 'vital_high':
      return 'Vital above threshold';
    case 'vital_low':
      return 'Vital below threshold';
  }
  return 'Alert';
}

IconData _eventIcon(String type) {
  switch (type) {
    case 'vital_high':
    case 'vital_low':
      return Icons.monitor_heart_rounded;
    case 'chat_crisis':
      return Icons.chat_bubble_rounded;
    case 'phq9_severe':
      return Icons.assignment_late_rounded;
    case 'sos':
      return Icons.sos_rounded;
  }
  return Icons.crisis_alert_rounded;
}

Color _severityColor(String severity) {
  switch (severity) {
    case 'critical':
      return AppTheme.riskRed;
    case 'high':
      return const Color(0xFFE37A42);
    case 'medium':
      return AppTheme.warningAmber;
  }
  // Unknown severity is treated as serious rather than hidden.
  return AppTheme.riskRed;
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

String _relative(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} days ago';
}

String _absolute(DateTime date) {
  final local = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _safeString(dynamic value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is num) return value.toString();
  return fallback;
}
