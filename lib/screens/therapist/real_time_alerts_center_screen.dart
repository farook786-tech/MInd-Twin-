import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class RealTimeAlertsCenterScreen extends StatelessWidget {
  const RealTimeAlertsCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final therapistId = FirebaseAuth.instance.currentUser?.uid;
    if (therapistId == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        appBar: AppBar(backgroundColor: AppTheme.cardDark, title: const Text('Real-Time Alerts Center')),
        body: const Center(
          child: Text('Please sign in as therapist.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Real-Time Alerts Center'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('crisis_events')
            .where('therapistId', isEqualTo: therapistId)
            .where('acknowledged', isEqualTo: false)
            .snapshots(),
        builder: (context, crisisSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('anomalies')
                .where('therapistId', isEqualTo: therapistId)
                .where('dismissed', isEqualTo: false)
                .snapshots(),
            builder: (context, anomalySnapshot) {
              final loading = crisisSnapshot.connectionState == ConnectionState.waiting ||
                  anomalySnapshot.connectionState == ConnectionState.waiting;

              if (loading) {
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
                );
              }

              final crisisDocs = (crisisSnapshot.data?.docs ?? const []).map((e) {
                final data = e.data();
                data['__docId'] = e.id;
                return data;
              }).toList()
                ..sort((a, b) => _timestampOf(b).compareTo(_timestampOf(a)));

              final anomalyDocs = (anomalySnapshot.data?.docs ?? const []).map((e) {
                final data = e.data();
                data['__docId'] = e.id;
                return data;
              }).toList()
                ..sort((a, b) => _timestampOf(b).compareTo(_timestampOf(a)));

              final hasAnyData = crisisDocs.isNotEmpty || anomalyDocs.isNotEmpty;
              final hasError = crisisSnapshot.hasError || anomalySnapshot.hasError;

              if (hasError && !hasAnyData) {
                return const Center(
                  child: Text(
                    'No alerts data available right now.',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              if (!hasAnyData) {
                return Center(
                  child: Container(
                    margin: const EdgeInsets.all(18),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.safeGreen.withValues(alpha: 0.35)),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 56, color: AppTheme.safeGreen),
                        SizedBox(height: 10),
                        Text(
                          '✅ All Clear',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'No active alerts',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Crisis Alerts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (crisisDocs.isEmpty)
                    _emptySection('No active crisis alerts.')
                  else
                    ...crisisDocs.map(
                      (alert) => _crisisCard(
                        context: context,
                        alert: alert,
                        therapistId: therapistId,
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Text(
                    'Anomaly Alerts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (anomalyDocs.isEmpty)
                    _emptySection('No active anomaly alerts.')
                  else
                    ...anomalyDocs.map(
                      (alert) => _anomalyCard(
                        context: context,
                        alert: alert,
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptySection(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
      ),
    );
  }

  Widget _crisisCard({
    required BuildContext context,
    required Map<String, dynamic> alert,
    required String therapistId,
  }) {
    final patientName = _safeString(alert['patientName'], fallback: _safeString(alert['patientId'], fallback: 'Patient'));
    final phrasesRaw = alert['matchedPhrases'];
    final phrases = phrasesRaw is List
        ? phrasesRaw.map((e) => e.toString()).join(', ')
        : _safeString(phrasesRaw, fallback: 'No matched phrases');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.riskRed.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.riskRed),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🚨 $patientName - Critical',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(phrases, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            _relative(_timestampOf(alert)),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.74), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _btn(
                label: 'Call Patient',
                color: Colors.white,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Calling $patientName...')),
                  );
                },
              ),
              _btn(
                label: 'Send Message',
                color: Colors.white,
                onTap: () async {
                  final patientId = _safeString(alert['patientId']);
                  if (patientId.isEmpty) return;
                  await FirebaseFirestore.instance.collection('messages').add({
                    'senderId': therapistId,
                    'receiverId': patientId,
                    'body': 'I am here with you now. Please respond when you can.',
                    'status': 'sent',
                    'timestamp': FieldValue.serverTimestamp(),
                  });

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Safety message sent.')),
                  );
                },
              ),
              _btn(
                label: 'Acknowledge',
                color: Colors.white,
                onTap: () async {
                  final docId = _safeString(alert['__docId']);
                  if (docId.isEmpty) return;
                  await FirebaseFirestore.instance.collection('crisis_events').doc(docId).update({
                    'acknowledged': true,
                    'acknowledgedAt': FieldValue.serverTimestamp(),
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _anomalyCard({
    required BuildContext context,
    required Map<String, dynamic> alert,
  }) {
    final patientName = _safeString(alert['patientName'], fallback: _safeString(alert['patientId'], fallback: 'Patient'));
    final severity = _safeString(alert['severity'], fallback: 'low').toLowerCase();
    final color = switch (severity) {
      'high' => AppTheme.riskRed,
      'medium' => AppTheme.warningAmber,
      _ => AppTheme.safeGreen,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$patientName - ${_safeString(alert['anomalyType'], fallback: 'Anomaly')}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _safeString(alert['description'], fallback: 'No description'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 4),
          Text(
            _relative(_timestampOf(alert)),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _btn(
                label: 'Schedule Session',
                color: color,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Session scheduling initiated.')),
                  );
                },
              ),
              _btn(
                label: 'Dismiss',
                color: color,
                onTap: () async {
                  final docId = _safeString(alert['__docId']);
                  if (docId.isEmpty) return;
                  await FirebaseFirestore.instance.collection('anomalies').doc(docId).update({
                    'dismissed': true,
                    'dismissedAt': FieldValue.serverTimestamp(),
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
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
}

DateTime _timestampOf(Map<String, dynamic> data) {
  final values = [data['timestamp'], data['updatedAt'], data['createdAt']];
  for (final value in values) {
    final date = _date(value);
    if (date != null) return date;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
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
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  return '${diff.inDays} days ago';
}

String _safeString(dynamic value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is num) return value.toString();
  return fallback;
}
