import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../services/clinical_scoring.dart';

/// Therapist-facing "Clinical status" for ONE patient, live from Firestore.
///
/// * Level comes ONLY from validated instruments (PHQ-9, GAD-7, C-SSRS
///   Screener) via [ClinicalScoring.computeStatus]; every reason names the
///   answer/score and its age.
/// * Check-in, text-classifier, statistical and wearable signals are listed
///   separately under "Early-warning signals (not diagnostic)" and never
///   change the level.
/// * A positive C-SSRS HIGH stays visible until a therapist acknowledges its
///   `crisis_events/assessment_<id>` alert.
///
/// Reads (allowed for the patient's current therapist by firestore.rules):
/// `users/{patientId}`, `clinical_assessments` where patientId == X ordered by
/// timestamp desc (index patientId+timestamp desc), `crisis_events` where
/// patientId == X && acknowledged == false.
class ClinicalStatusCard extends StatefulWidget {
  final String patientId;

  /// Extra non-diagnostic signals computed by the parent (e.g. the check-in
  /// anomaly detector). Shown under early warnings only.
  final List<EarlyWarning> extraEarlyWarnings;

  const ClinicalStatusCard({
    super.key,
    required this.patientId,
    this.extraEarlyWarnings = const [],
  });

  static const String footer = 'Decision support only. Not a diagnosis or prescription. '
      'Treatment and medication decisions require clinical assessment by a licensed professional.';

  static Color colorFor(ClinicalLevel level) {
    switch (level) {
      case ClinicalLevel.critical:
        return AppTheme.riskRed;
      case ClinicalLevel.high:
        return const Color(0xFFE37A42);
      case ClinicalLevel.moderate:
        return AppTheme.warningAmber;
      case ClinicalLevel.low:
        return const Color(0xFF8BC34A);
      case ClinicalLevel.none:
        return AppTheme.safeGreen;
    }
  }

  @override
  State<ClinicalStatusCard> createState() => _ClinicalStatusCardState();
}

class _ClinicalStatusCardState extends State<ClinicalStatusCard> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _user;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _assessments;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _crisis;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ClinicalStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientId != widget.patientId) _bind();
  }

  void _bind() {
    final db = FirebaseFirestore.instance;
    _user = db.collection('users').doc(widget.patientId).snapshots();
    _assessments = db
        .collection('clinical_assessments')
        .where('patientId', isEqualTo: widget.patientId)
        .orderBy('timestamp', descending: true)
        .limit(40)
        .snapshots();
    _crisis = db
        .collection('crisis_events')
        .where('patientId', isEqualTo: widget.patientId)
        .where('acknowledged', isEqualTo: false)
        .snapshots();
  }

  static DateTime? _toDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _user,
      builder: (context, userSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _assessments,
        builder: (context, aSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _crisis,
          builder: (context, cSnap) {
            final error = aSnap.error ?? cSnap.error;
            if (error != null) {
              return _shell(
                child: Text(
                  'Clinical status unavailable: ${error is FirebaseException ? (error.message ?? error.code) : error}.\n'
                  'Do not assume the patient is safe; review alerts and assessments directly.',
                  style: TextStyle(color: AppTheme.riskRed),
                ),
              );
            }
            if (!aSnap.hasData || !cSnap.hasData) {
              return _shell(child: const LinearProgressIndicator());
            }
            final now = DateTime.now();
            final assessments = aSnap.data!.docs
                .map((d) => AssessmentRecord.fromMap(d.id, d.data(), toDate: _toDate))
                .toList();
            final crisis = cSnap.data!.docs.map((d) {
              final m = d.data();
              return CrisisRecord(
                id: d.id,
                eventType: (m['eventType'] ?? '').toString(),
                severity: (m['severity'] ?? '').toString(),
                title: m['title']?.toString(),
                at: _toDate(m['timestamp']) ?? _toDate(m['clientCreatedAt']),
              );
            }).toList();

            final user = userSnap.data?.data() ?? const <String, dynamic>{};
            final vitals = user['latestVitals'];
            final hr = vitals is Map ? vitals['heartRate'] : null;
            final thresholds = user['vitalThresholds'];
            final warnings = [
              ...earlyWarningsFromSnapshot(
                checkInIndicator: _num(user['latestRiskScore']),
                checkInAt: _toDate(user['lastCheckInAt']),
                heartRate: hr is Map ? _num(hr['value']) : null,
                heartRateAt: hr is Map ? _toDate(hr['measuredAt']) : null,
                heartRateHigh: (thresholds is Map ? _num(thresholds['heartRateHigh']) : null) ?? 120,
                heartRateLow: (thresholds is Map ? _num(thresholds['heartRateLow']) : null) ?? 45,
              ),
              ...widget.extraEarlyWarnings,
            ];

            final status = ClinicalScoring.computeStatus(
              assessments: assessments,
              unacknowledgedCrisis: crisis,
              earlyWarnings: warnings,
              now: now,
            );
            return _buildStatus(status, now);
          },
        ),
      ),
    );
  }

  Widget _shell({required Widget child, Color? border}) {
    return Card(
      color: AppTheme.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border ?? AppColors.ink.withValues(alpha: 0.1), width: border == null ? 1 : 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Clinical status',
              style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 14),
            Divider(color: AppColors.ink24, height: 1),
            const SizedBox(height: 10),
            Text(
              ClinicalStatusCard.footer,
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6), fontSize: 11, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(ClinicalStatus s, DateTime now) {
    final color = s.hasInstrumentData ? ClinicalStatusCard.colorFor(s.level) : AppColors.ink54;
    final badge = s.hasInstrumentData ? s.level.label.toUpperCase() : 'NO DATA';
    final muted = TextStyle(color: AppColors.ink.withValues(alpha: 0.7), fontSize: 12);

    String dateOf(String key) {
      final d = s.instrumentDates[key];
      if (d == null) return '—';
      return '${DateFormat('MMM d').format(d.toLocal())} (${ClinicalScoring.describeAge(d, now)})';
    }

    String latest(List<int> h, int max) => h.isEmpty ? '—' : '${h.last}/$max';

    return _shell(
      border: s.level.rank >= ClinicalLevel.high.rank ? color : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color, width: 2),
                ),
                child: Text(badge, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.hasInstrumentData ? 'Primary driver: ${s.primaryDriver}' : s.primaryDriver,
                  style: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.assignment_turned_in_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Suggested workflow step: ${s.recommendedAction}',
                  style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          if (s.reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Why (validated instruments)', style: muted.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ...s.reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    r.startsWith('  ') ? r : '• $r',
                    style: TextStyle(
                      color: r.contains('STALE') ? AppTheme.warningAmber : AppColors.ink,
                      fontSize: 12.5,
                    ),
                  ),
                )),
          ],
          const SizedBox(height: 12),
          _instrumentRow('PHQ-9', latest(s.phq9History, 27), dateOf('phq9'), s.phq9History, 27),
          _instrumentRow('GAD-7', latest(s.gad7History, 21), dateOf('gad7'), s.gad7History, 21),
          _instrumentRow('C-SSRS', s.instrumentDates['cssrs'] == null ? '—' : 'see reasons', dateOf('cssrs'),
              const [], 1),
          const SizedBox(height: 12),
          Text(
            'Early-warning signals (not diagnostic)',
            style: muted.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          if (s.earlyWarnings.isEmpty)
            Text('—', style: muted)
          else
            ...s.earlyWarnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        w.flagged ? Icons.flag_rounded : Icons.circle_outlined,
                        size: 13,
                        color: w.flagged ? AppTheme.warningAmber : AppColors.ink38,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(w.describe(now), style: muted)),
                    ],
                  ),
                )),
          Text(
            'Heuristic and statistical signals from check-ins, text and wearables. They do not change the '
            'clinical status level and are not validated for diagnosis.',
            style: TextStyle(color: AppColors.ink.withValues(alpha: 0.45), fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _instrumentRow(String name, String value, String date, List<int> history, int max) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(name, style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
          SizedBox(width: 74, child: Text(value, style: TextStyle(color: AppColors.ink, fontSize: 12.5))),
          Expanded(
            child: Text(date, style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6), fontSize: 11.5)),
          ),
          SizedBox(
            width: 72,
            height: 22,
            child: history.length < 2
                ? const SizedBox.shrink()
                : Semantics(
                    label: '$name last ${history.length}: ${history.join(', ')}',
                    child: CustomPaint(painter: _SparklinePainter(history, max)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Minimal trend line, fixed 0..max scale (so heights are comparable).
class _SparklinePainter extends CustomPainter {
  final List<int> values;
  final int max;

  _SparklinePainter(this.values, this.max);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primaryIndigo
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final y = size.height - size.height * (values[i].clamp(0, max) / max);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    final last = values.length - 1;
    canvas.drawCircle(
      Offset(size.width, size.height - size.height * (values[last].clamp(0, max) / max)),
      2.5,
      Paint()..color = AppTheme.primaryIndigo,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.values != values || old.max != max;
}
