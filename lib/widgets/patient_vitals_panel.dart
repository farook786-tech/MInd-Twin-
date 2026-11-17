import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../services/vitals_repository.dart';

/// Live vitals for one patient (therapist detail screen or the patient's own twin screen).
///
/// Streams `vitals` where patientId == [patientId] and measuredAt >= now-24h (newest first),
/// plus `users/{patientId}.vitalThresholds`. Requires Firestore composite index
/// `vitals (patientId ASC, measuredAt DESC)`.
class PatientVitalsPanel extends StatelessWidget {
  const PatientVitalsPanel({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) => _VitalsPanelBody(patientId: patientId);
}

class _Thresholds {
  final double hrHigh;
  final double hrLow;
  final double sleepLow;
  const _Thresholds({this.hrHigh = 120, this.hrLow = 45, this.sleepLow = 4});

  factory _Thresholds.from(Map<String, dynamic>? user) {
    final t = user?['vitalThresholds'];
    if (t is! Map) return const _Thresholds();
    double pick(String k, double d) => (t[k] is num) ? (t[k] as num).toDouble() : d;
    return _Thresholds(
      hrHigh: pick('heartRateHigh', 120),
      hrLow: pick('heartRateLow', 45),
      sleepLow: pick('sleepHoursLow', 4),
    );
  }
}

class _VitalsPanelBody extends StatefulWidget {
  const _VitalsPanelBody({required this.patientId});
  final String patientId;

  @override
  State<_VitalsPanelBody> createState() => _VitalsPanelBodyState();
}

class _VitalsPanelBodyState extends State<_VitalsPanelBody> {
  static const _window = Duration(hours: 24);
  static const _staleAfter = Duration(hours: 2);

  final _repo = VitalsRepository();
  late Stream<List<VitalReading>> _vitals;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _user;
  late DateTime _windowStart;
  Timer? _tick;
  int _lastWindowHour = -1;

  @override
  void initState() {
    super.initState();
    _subscribe();
    // Refresh "x min ago" every minute; slide the 24 h window every hour.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (DateTime.now().hour != _lastWindowHour) _subscribe();
      });
    });
  }

  @override
  void didUpdateWidget(covariant _VitalsPanelBody old) {
    super.didUpdateWidget(old);
    if (old.patientId != widget.patientId) _subscribe();
  }

  void _subscribe() {
    final now = DateTime.now();
    _lastWindowHour = now.hour;
    _windowStart = now.subtract(_window);
    _vitals = _repo.watchSince(widget.patientId, _windowStart);
    _user = FirebaseFirestore.instance.collection('users').doc(widget.patientId).snapshots();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _user,
      builder: (context, userSnap) {
        final thresholds = _Thresholds.from(userSnap.data?.data());
        return StreamBuilder<List<VitalReading>>(
          stream: _vitals,
          builder: (context, snap) {
            if (snap.hasError) {
              return _card(Text(
                'Could not load vitals: ${snap.error}',
                style: const TextStyle(color: AppTheme.riskRed, fontSize: 13),
              ));
            }
            if (!snap.hasData) {
              return _card(const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator(color: AppTheme.primaryIndigo)),
              ));
            }
            return _card(_content(snap.data!, thresholds));
          },
        );
      },
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.glassDecoration(accentColor: AppTheme.primaryIndigo, borderRadius: 16),
        child: child,
      );

  Widget _content(List<VitalReading> all, _Thresholds th) {
    final now = DateTime.now();
    final hr = all
        .where((r) => r.type == VitalType.heartRate && r.value.isFinite)
        .toList(); // newest first
    final latestHr = hr.isNotEmpty ? hr.first : null;
    final latestSleep = all.where((r) => r.type == VitalType.sleep).firstOrNull;
    final today = DateTime(now.year, now.month, now.day);
    final todaySteps = all
        .where((r) => r.type == VitalType.steps && !r.measuredAt.toLocal().isBefore(today))
        .firstOrNull;

    final hrColor = latestHr == null ? Colors.white54 : _hrColor(latestHr.value, th);
    final staleFor = latestHr == null ? null : now.difference(latestHr.measuredAt.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.monitor_heart_outlined, color: AppTheme.primaryIndigo, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Vitals (last 24 h)',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (latestHr != null)
            Text(_source(latestHr.source), style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
        if (latestHr == null)
          _warning('No heart-rate data received in the last 24 hours.')
        else if (staleFor! > _staleAfter)
          _warning('No data from watch in ${_duration(staleFor)}.'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              latestHr == null ? '--' : latestHr.value.round().toString(),
              style: TextStyle(color: hrColor, fontSize: 36, fontWeight: FontWeight.w900, height: 1),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('BPM', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            const Spacer(),
            if (latestHr != null)
              Text(
                _ago(now.difference(latestHr.measuredAt.toLocal())),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Alert range: below ${th.hrLow.round()} or above ${th.hrHigh.round()} BPM',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 150, child: _chart(hr, th, now)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _tile(
              icon: Icons.bedtime_outlined,
              label: 'Last night sleep',
              value: latestSleep == null ? 'No data' : '${latestSleep.value.toStringAsFixed(1)} h',
              color: latestSleep == null
                  ? Colors.white54
                  : (latestSleep.value < th.sleepLow ? AppTheme.riskRed : AppTheme.safeGreen),
              sub: latestSleep == null
                  ? null
                  : 'woke ${DateFormat('EEE HH:mm').format(latestSleep.measuredAt.toLocal())}',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile(
              icon: Icons.directions_walk,
              label: 'Steps today',
              value: todaySteps == null
                  ? 'No data'
                  : NumberFormat.decimalPattern().format(todaySteps.value.round()),
              color: todaySteps == null ? Colors.white54 : AppTheme.accentCyan,
              sub: todaySteps == null
                  ? null
                  : 'as of ${DateFormat('HH:mm').format(todaySteps.measuredAt.toLocal())}',
            ),
          ),
        ]),
      ],
    );
  }

  Color _hrColor(double bpm, _Thresholds th) {
    if (bpm > th.hrHigh || bpm < th.hrLow) return AppTheme.riskRed;
    final margin = (th.hrHigh - th.hrLow) * 0.1;
    if (bpm > th.hrHigh - margin || bpm < th.hrLow + margin) return AppTheme.warningAmber;
    return AppTheme.safeGreen;
  }

  Widget _chart(List<VitalReading> hrNewestFirst, _Thresholds th, DateTime now) {
    if (hrNewestFirst.isEmpty) {
      return const Center(
        child: Text('No heart-rate readings to chart', style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }
    final start = _windowStart;
    final points = hrNewestFirst.reversed.toList();
    final spots = <FlSpot>[];
    DateTime? prev;
    for (final r in points) {
      final t = r.measuredAt.toLocal();
      if (t.isBefore(start)) continue;
      // Break the line across gaps > 30 min instead of drawing a fake trend.
      if (prev != null && t.difference(prev) > const Duration(minutes: 30)) spots.add(FlSpot.nullSpot);
      spots.add(FlSpot(t.difference(start).inSeconds / 3600.0, r.value));
      prev = t;
    }
    final values = points.map((r) => r.value);
    final minY = ([...values, th.hrLow].reduce((a, b) => a < b ? a : b) - 10).clamp(0, 300).toDouble();
    final maxY = ([...values, th.hrHigh].reduce((a, b) => a > b ? a : b) + 10).toDouble();
    final maxX = now.difference(start).inSeconds / 3600.0;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: 0.06), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(y: th.hrHigh, color: AppTheme.riskRed.withValues(alpha: 0.6), strokeWidth: 1, dashArray: [4, 4]),
          HorizontalLine(y: th.hrLow, color: AppTheme.riskRed.withValues(alpha: 0.6), strokeWidth: 1, dashArray: [4, 4]),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 20,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(v.round().toString(), style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 6,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  DateFormat('HH:mm').format(start.add(Duration(minutes: (v * 60).round()))),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (items) => items
                .map((s) => LineTooltipItem(
                      '${s.y.round()} BPM\n'
                      '${DateFormat('HH:mm').format(start.add(Duration(seconds: (s.x * 3600).round())))}',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.pinkAccent,
            barWidth: 2,
            dotData: FlDotData(show: spots.length < 3),
            belowBarData: BarAreaData(show: true, color: Colors.pinkAccent.withValues(alpha: 0.08)),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        if (sub != null) Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    );
  }

  Widget _warning(String text) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.warningAmber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.warningAmber.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.watch_off_outlined, color: AppTheme.warningAmber, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.warningAmber, fontSize: 12))),
        ]),
      );

  static String _source(String s) => switch (s) {
        'wear_os' => 'Galaxy Watch (Wear OS)',
        'health_connect' => 'Health Connect',
        _ => s,
      };

  static String _duration(Duration d) {
    if (d.inHours >= 1) {
      final h = d.inHours;
      return '$h hour${h == 1 ? '' : 's'}';
    }
    return '${d.inMinutes} min';
  }

  static String _ago(Duration d) {
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ${d.inMinutes % 60} min ago';
    return '${d.inDays} d ago';
  }
}
