import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../services/clinical_scoring.dart' show AssessmentRecord;
import '../services/daily_log_source.dart';
import '../services/digital_twin_service.dart';

/// "Digital Twin drift" card: the patient's recent pattern vs their own 28-day
/// baseline ([DigitalTwinService]). Early-warning only; never a diagnosis and never
/// part of the clinical level.
///
/// * Therapist view: index 0-100, level, explanations, per-signal status.
/// * Patient view: gentle wording, stable / "some changes" only, 28-day sparkline per
///   signal; no index, no z-scores.
///
/// Reads ONCE per open / refresh (no listeners): `vitals_daily` (<= 31 docs, index
/// patientId ASC + date DESC), `daily_logs` (<= 60, therapist-scoped via
/// [DailyLogSource.scopedQuery]) and `clinical_assessments` (<= 40). ~130 reads max.
class TwinDriftCard extends StatefulWidget {
  final String patientId;
  final bool therapistView;

  /// Called after every successful computation (e.g. to add the drift entry to the
  /// Clinical status card's early-warning list).
  final ValueChanged<DriftResult>? onResult;

  const TwinDriftCard({super.key, required this.patientId, this.therapistView = false, this.onResult});

  static const String therapistLabel = 'Early-warning, personal-baseline signal — not diagnostic';

  @override
  State<TwinDriftCard> createState() => _TwinDriftCardState();
}

class _TwinDriftCardState extends State<TwinDriftCard> {
  late Future<DriftResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant TwinDriftCard old) {
    super.didUpdateWidget(old);
    if (old.patientId != widget.patientId) _future = _load();
  }

  static DateTime? _toDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

  Future<DriftResult> _load() async {
    final db = FirebaseFirestore.instance;
    final pid = widget.patientId;
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day - DigitalTwinService.spanDays);

    final results = await Future.wait([
      db
          .collection('vitals_daily')
          .where('patientId', isEqualTo: pid)
          .orderBy('date', descending: true)
          .limit(DigitalTwinService.spanDays + 3)
          .get(),
      DailyLogSource.scopedQuery(pid).limit(60).get(),
      db
          .collection('clinical_assessments')
          .where('patientId', isEqualTo: pid)
          .orderBy('timestamp', descending: true)
          .limit(40)
          .get(),
    ]);

    final data = <DriftSignal, List<DatedValue>>{};
    DigitalTwinService.addVitalsDaily(data, results[0].docs.map((d) => d.data()));
    DigitalTwinService.addDailyLogs(data, [
      for (final d in results[1].docs)
        if (_toDate(d.data()['timestamp']) case final at? when at.isAfter(since))
          (at: at, wellbeing: _num(d.data()['wellbeingScore']), riskScore: _num(d.data()['riskScore'])),
    ]);
    DigitalTwinService.addAssessments(
      data,
      results[2].docs.map((d) => AssessmentRecord.fromMap(d.id, d.data(), toDate: _toDate)),
    );
    final r = DigitalTwinService.compute(data: data, now: now);
    widget.onResult?.call(r);
    return r;
  }

  void _refresh() => setState(() => _future = _load());

  Color _levelColor(DriftLevel l) => switch (l) {
        DriftLevel.learning => AppColors.ink54,
        DriftLevel.stable => AppTheme.safeGreen,
        DriftLevel.watch => AppTheme.warningAmber,
        DriftLevel.drifting => widget.therapistView ? AppTheme.riskRed : AppTheme.warningAmber,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.ink.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<DriftResult>(
          future: _future,
          builder: (context, snap) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.timeline, color: AppTheme.primaryIndigo, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.therapistView ? 'Digital Twin drift' : 'Your recent pattern vs your usual',
                      style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.refresh, size: 18, color: AppColors.ink54),
                    onPressed: snap.connectionState == ConnectionState.waiting ? null : _refresh,
                  ),
                ]),
                if (widget.therapistView)
                  Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(TwinDriftCard.therapistLabel,
                        style: TextStyle(color: AppColors.ink60, fontSize: 11, fontStyle: FontStyle.italic)),
                  )
                else
                  const SizedBox(height: 8),
                if (snap.hasError)
                  Text(
                    widget.therapistView
                        ? 'Drift unavailable: ${snap.error is FirebaseException ? ((snap.error as FirebaseException).message ?? (snap.error as FirebaseException).code) : snap.error}'
                        : 'Could not load your pattern right now.',
                    style: TextStyle(color: AppColors.ink70, fontSize: 12),
                  )
                else if (!snap.hasData)
                  const LinearProgressIndicator()
                else
                  widget.therapistView ? _therapist(snap.data!) : _patient(snap.data!),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _therapist(DriftResult r) {
    final color = _levelColor(r.level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(
            r.index == null ? '--' : '${r.index}',
            style: TextStyle(color: color, fontSize: 30, fontWeight: FontWeight.w900, height: 1),
          ),
          Text(' /100', style: TextStyle(color: AppColors.ink54, fontSize: 13)),
          const SizedBox(width: 12),
          _chip(r.level.label.toUpperCase(), color),
        ]),
        const SizedBox(height: 10),
        for (final line in r.explanations)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6))),
              Expanded(
                child: Text(line, style: TextStyle(color: AppColors.ink70, fontSize: 12, height: 1.3)),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Text(
          'Compares the last 3 days (PHQ-9/GAD-7: last 7) with this patient\'s own 28-day baseline '
          '(median ± MAD), worse direction only. Does not change the Clinical status level.',
          style: TextStyle(color: AppColors.ink.withValues(alpha: 0.5), fontSize: 10.5, height: 1.3),
        ),
      ],
    );
  }

  Widget _patient(DriftResult r) {
    final color = _levelColor(r.level);
    final shown = r.signals.where((s) => s.hasAnyData).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chip(r.level.patientLabel, color),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Text(
            'Once you have a week of check-ins or watch data, you\'ll see how your recent days compare '
            'with your own usual pattern here.',
            style: TextStyle(color: AppColors.ink70, fontSize: 12, height: 1.35),
          ),
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.spec.patientLabel,
                      style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(s.patientText,
                      style: TextStyle(color: AppColors.ink60, fontSize: 11, height: 1.3)),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 32,
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      values: s.series,
                      baseline: s.baselineMedian,
                      color: (s.score ?? 0) >= 1 ? AppTheme.warningAmber : AppTheme.accentCyan,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        Text(
          'This compares you only with yourself over the last 4 weeks. It is not a diagnosis. '
          'If you are finding things hard, message your therapist.',
          style: TextStyle(color: AppColors.ink.withValues(alpha: 0.5), fontSize: 10.5, height: 1.3),
        ),
      ],
    );
  }
}

/// 28-day sparkline: line segments only between consecutive days with data (gaps stay
/// gaps), faint dashed line at the personal baseline median.
class _SparklinePainter extends CustomPainter {
  final List<double?> values;
  final double? baseline;
  final Color color;

  _SparklinePainter({required this.values, required this.baseline, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList();
    if (present.isEmpty) return;
    var lo = present.reduce((a, b) => a < b ? a : b);
    var hi = present.reduce((a, b) => a > b ? a : b);
    if (baseline != null) {
      lo = lo < baseline! ? lo : baseline!;
      hi = hi > baseline! ? hi : baseline!;
    }
    if (hi - lo < 1e-9) {
      hi += 1;
      lo -= 1;
    }
    final n = values.length;
    double x(int i) => n <= 1 ? size.width / 2 : i * size.width / (n - 1);
    double y(double v) => size.height - 2 - (v - lo) / (hi - lo) * (size.height - 4);

    if (baseline != null) {
      final p = Paint()
        ..color = AppColors.ink24
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 6) {
        canvas.drawLine(Offset(dx, y(baseline!)), Offset(dx + 3, y(baseline!)), p);
      }
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final prev = i > 0 ? values[i - 1] : null;
      if (prev != null) canvas.drawLine(Offset(x(i - 1), y(prev)), Offset(x(i), y(v)), line);
      final next = i + 1 < n ? values[i + 1] : null;
      if (prev == null && next == null) canvas.drawCircle(Offset(x(i), y(v)), 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.baseline != baseline || old.color != color;
}
