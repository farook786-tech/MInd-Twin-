import 'package:flutter_test/flutter_test.dart';
import 'package:mindtwin/services/vitals_aggregation.dart';
import 'package:mindtwin/services/vitals_repository.dart';

VitalReading hr(DateTime at, double bpm) =>
    VitalReading(type: VitalType.heartRate, value: bpm, measuredAt: at, source: 'wear_os');

void main() {
  final t0 = DateTime.utc(2026, 11, 17, 10, 0); // aligned to 5 min

  group('HeartRateAggregation.aggregate', () {
    test('one window per 5 minutes with mean / min / max / count', () {
      final samples = [
        hr(t0.add(const Duration(minutes: 0)), 60),
        hr(t0.add(const Duration(minutes: 2)), 70),
        hr(t0.add(const Duration(minutes: 4, seconds: 59)), 80),
        hr(t0.add(const Duration(minutes: 5)), 100), // next window
      ];
      final w = HeartRateAggregation.aggregate(samples);
      expect(w, hasLength(2));
      expect(w[0].start, t0);
      expect(w[0].end, t0.add(const Duration(minutes: 5)));
      expect(w[0].count, 3);
      expect(w[0].avg, 70);
      expect(w[0].min, 60);
      expect(w[0].max, 80);
      expect(w[1].count, 1);
      expect(w[1].roundedAvg, 100);
    });

    test('ignores implausible values and other vital types; never invents windows', () {
      final w = HeartRateAggregation.aggregate([
        hr(t0, 10),
        hr(t0, 400),
        hr(t0, double.nan),
        VitalReading(type: VitalType.sleep, value: 7, measuredAt: t0, source: 'health_connect'),
      ]);
      expect(w, isEmpty);
      // A 1-hour gap produces no windows in between.
      final gap = HeartRateAggregation.aggregate([hr(t0, 60), hr(t0.add(const Duration(hours: 1)), 62)]);
      expect(gap, hasLength(2));
    });

    test('window ids are aligned and deterministic (dedupe)', () {
      final w = HeartRateAggregation.aggregate([hr(t0.add(const Duration(minutes: 7)), 64)]).single;
      expect(w.startMillis % HeartRateAggregation.windowMillis, 0);
      final doc = VitalReading(
        type: VitalType.heartRate,
        value: 64,
        measuredAt: w.end,
        source: 'wear_os',
        windowStart: w.start,
        min: 64,
        max: 64,
        sampleCount: 1,
      );
      expect(doc.docId('p1'), 'p1_heart_rate_${w.startMillis}');
      final imm = VitalReading(
          type: VitalType.heartRate, value: 130, measuredAt: t0, source: 'wear_os', immediate: true);
      expect(imm.docId('p1'), 'p1_heart_rate_imm_${t0.millisecondsSinceEpoch}');
      expect(doc.toFields()['measuredAt'], isNotNull);
      expect(doc.toFields().keys, containsAll(['min', 'max', 'sampleCount', 'windowStart']));
      expect(imm.toFields()['immediate'], true);
      expect(imm.toFields().containsKey('min'), isFalse);
    });

    test('a day of 1/min samples becomes 288 docs instead of 1440', () {
      final samples = [for (var i = 0; i < 1440; i++) hr(t0.add(Duration(minutes: i)), 70)];
      expect(HeartRateAggregation.aggregate(samples), hasLength(288));
    });
  });

  group('HeartRateAggregation.selectImmediate', () {
    const th = HrThresholds();

    test('only out-of-range samples, at most one per direction per window', () {
      final out = HeartRateAggregation.selectImmediate([
        hr(t0, 80),
        hr(t0.add(const Duration(minutes: 1)), 125),
        hr(t0.add(const Duration(minutes: 2)), 128), // same window, same direction -> skipped
        hr(t0.add(const Duration(minutes: 3)), 44), // other direction -> kept
        hr(t0.add(const Duration(minutes: 6)), 126), // next window -> kept
      ], th);
      expect(out.map((r) => r.value), [125, 44, 126]);
    });

    test('a sample that turns critical in the same window is still sent once', () {
      final out = HeartRateAggregation.selectImmediate([
        hr(t0, 125),
        hr(t0.add(const Duration(minutes: 1)), 155),
        hr(t0.add(const Duration(minutes: 2)), 160),
      ], th);
      expect(out.map((r) => r.value), [125, 155]);
    });

    test('boundaries are strict (same as the server: > high, < low)', () {
      expect(HeartRateAggregation.selectImmediate([hr(t0, 120), hr(t0, 45)], th), isEmpty);
    });

    test('per-patient thresholds from users doc, validated like the server', () {
      expect(
          HrThresholds.fromUserDoc({
            'vitalThresholds': {'heartRateHigh': 100}
          }).high,
          100);
      expect(
          HrThresholds.fromUserDoc({
            'vitalThresholds': {'heartRateHigh': 1000}
          }).high,
          120);
      final inverted = HrThresholds.fromUserDoc({
        'vitalThresholds': {'heartRateHigh': 80, 'heartRateLow': 80}
      });
      expect([inverted.high, inverted.low], [120, 45]);
      expect(HrThresholds.fromUserDoc(null).low, 45);
    });
  });

  group('HeartRateAggregation.summarizeDay', () {
    HrWindow w(int i, double avg, {double? min, double? max}) => HrWindow(
          start: t0.add(Duration(minutes: 5 * i)),
          sum: avg * 5,
          count: 5,
          min: min ?? avg,
          max: max ?? avg,
        );

    test('resting = nearest-rank 10th percentile of window means; avg/min/max', () {
      final windows = [for (var i = 0; i < 20; i++) w(i, 60.0 + i, min: 55.0 + i, max: 70.0 + i)];
      final s = HeartRateAggregation.summarizeDay(windows)!;
      expect(s.restingEstimate, 61); // ceil(0.1*20)=2nd smallest = 61
      expect(s.avg, 70); // mean of 60..79 = 69.5 -> 70
      expect(s.min, 55);
      expect(s.max, 89);
      expect(s.windows, 20);
    });

    test('no resting estimate with < 1 h of windows; null with no data', () {
      final s = HeartRateAggregation.summarizeDay([for (var i = 0; i < 11; i++) w(i, 70)])!;
      expect(s.restingEstimate, isNull);
      expect(HeartRateAggregation.summarizeDay(const []), isNull);
    });

    test('percentile helper', () {
      expect(HeartRateAggregation.percentile([], 0.1), isNull);
      expect(HeartRateAggregation.percentile([5], 0.1), 5);
      expect(HeartRateAggregation.percentile([3, 1, 2], 0.5), 2);
    });

    test('local date key', () {
      expect(HeartRateAggregation.localDateKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
      expect(HeartRateAggregation.dailyDocId('p1', '2026-01-05'), 'p1_2026-01-05');
    });
  });
}
