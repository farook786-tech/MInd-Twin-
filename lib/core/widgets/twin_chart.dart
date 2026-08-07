import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import 'app_card.dart';

/// A single day of the patient's twin data.
class TwinChartPoint {
  final DateTime timestamp;
  final double? mood; // 1-5 (1 = best)
  final double? sleep; // 1-4 (1 = best)
  final double? energy; // 1-4 (1 = best)
  final double? risk; // 0-100

  const TwinChartPoint({
    required this.timestamp,
    this.mood,
    this.sleep,
    this.energy,
    this.risk,
  });
}

/// Shared 7-day trend chart used on Home and My Twin.
/// Normalizes all series onto a 0-10 Y axis and colors them with theme
/// palette colors, with an on-tap tooltip and legend.
class TwinTrendChart extends StatelessWidget {
  final List<TwinChartPoint> points; // ascending by timestamp
  final double height;
  final void Function(int index)? onPointSelected;
  final int? selectedIndex;
  final bool showLegend;

  const TwinTrendChart({
    super.key,
    required this.points,
    this.height = 200,
    this.onPointSelected,
    this.selectedIndex,
    this.showLegend = true,
  });

  static const Color moodColor = AppColors.primaryCyan; // #00F0FF
  static const Color sleepColor = AppColors.primaryTeal; // #00E676
  static const Color energyColor = AppColors.primaryViolet; // #8A2BE2
  static const Color riskColor = AppColors.healthWarning; // #FFB300

  @override
  Widget build(BuildContext context) {
    final sorted = List<TwinChartPoint>.from(points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final moodSpots = <FlSpot>[];
    final sleepSpots = <FlSpot>[];
    final energySpots = <FlSpot>[];
    final riskSpots = <FlSpot>[];

    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (p.mood != null) moodSpots.add(FlSpot(i.toDouble(), (p.mood! / 5.0) * 10.0));
      if (p.sleep != null) sleepSpots.add(FlSpot(i.toDouble(), (p.sleep! / 4.0) * 10.0));
      if (p.energy != null) energySpots.add(FlSpot(i.toDouble(), (p.energy! / 4.0) * 10.0));
      if (p.risk != null) riskSpots.add(FlSpot(i.toDouble(), (p.risk! / 10.0).clamp(0.0, 10.0)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: sorted.length <= 1 ? 1 : (sorted.length - 1).toDouble(),
              minY: 0,
              maxY: 10,
              clipData: const FlClipData.all(),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: Colors.black87,
                  tooltipRoundedRadius: 8,
                  tooltipBorder: const BorderSide(
                    color: AppColors.primaryCyan,
                    width: 1,
                  ),
                ),
                touchCallback: (event, response) {
                  if (onPointSelected == null) return;
                  if (event is FlTapUpEvent || event is FlPanEndEvent) {
                    final spots = response?.lineBarSpots;
                    if (spots == null || spots.isEmpty) return;
                    onPointSelected!(spots.first.x.toInt());
                  }
                },
              ),
              gridData: FlGridData(
                show: true,
                horizontalInterval: 2,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.white.withValues(alpha: 0.1),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 2,
                    reservedSize: 26,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, _) {
                      final index = value.toInt();
                      if (index < 0 || index >= sorted.length) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        DateFormat('EEE').format(sorted[index].timestamp),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                _series(moodSpots, moodColor),
                _series(sleepSpots, sleepColor),
                _series(energySpots, energyColor),
                _series(riskSpots, riskColor),
              ],
            ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 10),
          const Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              LegendChip(color: TwinTrendChart.moodColor, label: 'Mood'),
              LegendChip(color: TwinTrendChart.sleepColor, label: 'Sleep'),
              LegendChip(color: TwinTrendChart.energyColor, label: 'Energy'),
              LegendChip(color: TwinTrendChart.riskColor, label: 'Risk'),
            ],
          ),
        ],
      ],
    );
  }

  LineChartBarData _series(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: true),
    );
  }
}
