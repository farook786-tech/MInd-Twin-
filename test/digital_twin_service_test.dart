import 'package:flutter_test/flutter_test.dart';
import 'package:mindtwin/services/clinical_scoring.dart';
import 'package:mindtwin/services/digital_twin_service.dart';

final now = DateTime(2026, 11, 17, 20, 0);
DateTime daysAgo(int n) => DateTime(now.year, now.month, now.day - n, 9);

/// [base] for days 4..27 ago (+ small deterministic wobble), [recent] for days 0..3 ago.
List<DatedValue> series(double base, double recent, {double wobble = 1, int from = 27, int recentFrom = 3}) =>
    [
      for (var d = from; d > recentFrom; d--) DatedValue(daysAgo(d), base + ((d % 3) - 1) * wobble),
      for (var d = recentFrom; d >= 0; d--) DatedValue(daysAgo(d), recent),
    ];

SignalDrift sig(DriftResult r, DriftSignal s) => r.signals.firstWhere((x) => x.spec.signal == s);

void main() {
  group('robust statistics', () {
    test('median / MAD', () {
      expect(DigitalTwinService.median([3, 1, 2]), 2);
      expect(DigitalTwinService.median([4, 1, 2, 3]), 2.5);
      expect(DigitalTwinService.median([]), isNull);
      expect(DigitalTwinService.mad([1, 2, 3, 4, 100]), 1);
    });
  });

  group('compute', () {
    test('stable when everything matches the personal baseline', () {
      final r = DigitalTwinService.compute(now: now, data: {
        DriftSignal.restingHr: series(64, 64),
        DriftSignal.sleep: series(7.2, 7.2, wobble: 0.3),
        DriftSignal.steps: series(8000, 8000, wobble: 500),
        DriftSignal.checkIn: series(70, 70, wobble: 4),
      });
      expect(r.index, 0);
      expect(r.level, DriftLevel.stable);
      expect(r.contributing, isEmpty);
    });

    test('worse direction only: resting HR up counts, resting HR down does not', () {
      final up = DigitalTwinService.compute(now: now, data: {DriftSignal.restingHr: series(64, 78)});
      final down = DigitalTwinService.compute(now: now, data: {DriftSignal.restingHr: series(64, 52)});
      expect(sig(up, DriftSignal.restingHr).score, greaterThan(2));
      expect(sig(down, DriftSignal.restingHr).score, 0);
      expect(
          sig(up, DriftSignal.restingHr).therapistText,
          allOf(contains('Resting HR 78 bpm vs your usual 64 bpm'), contains('MAD'),
              contains('3 of last 3 days')));
    });

    test('sleep: less is worse; far above baseline (hypersomnia) also counts', () {
      final less =
          DigitalTwinService.compute(now: now, data: {DriftSignal.sleep: series(7.2, 4.9, wobble: 0.3)});
      final bitMore =
          DigitalTwinService.compute(now: now, data: {DriftSignal.sleep: series(7.2, 7.9, wobble: 0.3)});
      final farMore =
          DigitalTwinService.compute(now: now, data: {DriftSignal.sleep: series(7.2, 11, wobble: 0.3)});
      expect(sig(less, DriftSignal.sleep).score, greaterThan(2));
      expect(sig(less, DriftSignal.sleep).therapistText, contains('Sleep 4.9 h vs your usual 7.2 h'));
      expect(sig(bitMore, DriftSignal.sleep).score, 0);
      expect(sig(farMore, DriftSignal.sleep).score, greaterThan(2));
      expect(sig(farMore, DriftSignal.sleep).therapistText, contains('much more than usual'));
    });

    test('monotonic: a larger worse-direction deviation never lowers the index', () {
      int? prev;
      for (final hr in <double>[64, 66, 68, 70, 74, 80, 90, 120]) {
        final r = DigitalTwinService.compute(now: now, data: {
          DriftSignal.restingHr: series(64, hr),
          DriftSignal.sleep: series(7, 6.5, wobble: 0.3),
        });
        if (prev != null) expect(r.index!, greaterThanOrEqualTo(prev));
        prev = r.index;
      }
      int? prevSteps;
      for (final steps in <double>[8000, 6000, 4000, 2000, 500]) {
        final r = DigitalTwinService.compute(now: now, data: {
          DriftSignal.steps: series(8000, steps, wobble: 500),
          DriftSignal.checkIn: series(70, 60, wobble: 4),
        });
        if (prevSteps != null) expect(r.index!, greaterThanOrEqualTo(prevSteps));
        prevSteps = r.index;
      }
    });

    test('bounded: index stays within 0..100 for extreme values; per-signal score capped at 4', () {
      final r = DigitalTwinService.compute(now: now, data: {
        DriftSignal.restingHr: series(60, 200),
        DriftSignal.sleep: series(8, 0.1, wobble: 0.1),
        DriftSignal.steps: series(10000, 0, wobble: 100),
        DriftSignal.checkIn: series(90, 0, wobble: 1),
      });
      expect(r.index, 100);
      expect(r.level, DriftLevel.drifting);
      expect(r.signals.where((s) => s.scored).every((s) => s.score! <= 4), isTrue);
    });

    test('missing data is never fabricated: absent signals are listed as no data', () {
      final r = DigitalTwinService.compute(now: now, data: {DriftSignal.restingHr: series(64, 64)});
      expect(sig(r, DriftSignal.sleep).therapistText, 'Sleep: no data');
      expect(sig(r, DriftSignal.sleep).series.every((v) => v == null), isTrue);
      expect(sig(r, DriftSignal.phq9).scored, isFalse);
      // Missing signals do not dilute the index: one scored signal decides it alone.
      final one = DigitalTwinService.compute(now: now, data: {DriftSignal.restingHr: series(64, 90)});
      expect(one.index, greaterThan(0));
      // Gaps stay gaps in the sparkline.
      final gappy = [
        for (final d in [27, 20, 15, 12, 10, 8, 6, 5]) DatedValue(daysAgo(d), 64),
        DatedValue(daysAgo(2), 64),
        DatedValue(daysAgo(1), 64),
      ];
      final g = sig(
          DigitalTwinService.compute(now: now, data: {DriftSignal.restingHr: gappy}), DriftSignal.restingHr);
      expect(g.series.where((v) => v != null).length, 10);
      expect(g.scored, isTrue);
    });

    test('short history: learning baseline N/7 days; no index', () {
      final r = DigitalTwinService.compute(now: now, data: {
        DriftSignal.restingHr: series(64, 90, from: 8), // baseline days 8..4 = 5 days
      });
      final hr = sig(r, DriftSignal.restingHr);
      expect(hr.scored, isFalse);
      expect(hr.therapistText, 'Resting HR: learning baseline: 5/7 days');
      expect(hr.patientText, 'Learning your usual: 5 of 7 days');
      expect(r.index, isNull);
      expect(r.level, DriftLevel.learning);
      expect(r.toEarlyWarning(), isNull);
    });

    test('recent window needs 2 of 3 days for daily signals', () {
      final vals = [
        for (var d = 27; d > 3; d--) DatedValue(daysAgo(d), 7),
        DatedValue(daysAgo(0), 3), // only one recent night
      ];
      final s = sig(DigitalTwinService.compute(now: now, data: {DriftSignal.sleep: vals}), DriftSignal.sleep);
      expect(s.scored, isFalse);
      expect(s.therapistText, contains('no recent data'));
    });

    test("today's partial steps / resting HR are excluded (3 complete days ending yesterday)", () {
      final vals = [
        for (var d = 27; d > 0; d--) DatedValue(daysAgo(d), 8000.0 + (d % 3) * 300),
        DatedValue(daysAgo(0), 300), // 9 am: partial day
      ];
      final s = sig(DigitalTwinService.compute(now: now, data: {DriftSignal.steps: vals}), DriftSignal.steps);
      expect(s.score, 0);
    });

    test('outliers in the baseline do not move the robust baseline', () {
      final clean = series(64, 72);
      final withOutliers = [
        ...clean,
        DatedValue(daysAgo(20), 140), // same day averaged -> one extreme day
        DatedValue(daysAgo(10), 20),
      ];
      final a = sig(
          DigitalTwinService.compute(now: now, data: {DriftSignal.restingHr: clean}), DriftSignal.restingHr);
      final b = sig(DigitalTwinService.compute(now: now, data: {DriftSignal.restingHr: withOutliers}),
          DriftSignal.restingHr);
      expect((a.baselineMedian! - b.baselineMedian!).abs(), lessThanOrEqualTo(1));
      expect(b.score, greaterThan(1));
    });

    test('a perfectly regular baseline (MAD = 0) uses the scale floor, not infinity', () {
      final s = sig(
          DigitalTwinService.compute(now: now, data: {DriftSignal.restingHr: series(64, 65, wobble: 0)}),
          DriftSignal.restingHr);
      expect(s.scale, 3);
      expect(s.robustZ, closeTo(1 / 3, 1e-9));
    });

    test('PHQ-9 / GAD-7: up is worse; needs >= 2 earlier results; latest of last 7 days', () {
      AssessmentRecord phq(int d, int total) =>
          AssessmentRecord(id: 'a$d', type: 'phq9', at: daysAgo(d), phq9Total: total);
      final data = <DriftSignal, List<DatedValue>>{};
      DigitalTwinService.addAssessments(data, [phq(26, 6), phq(19, 8), phq(12, 7), phq(2, 15)]);
      final r = DigitalTwinService.compute(now: now, data: data);
      final p = sig(r, DriftSignal.phq9);
      expect(p.baselineMedian, 7);
      expect(p.recent, 15);
      expect(p.score, greaterThanOrEqualTo(3));
      // One strong signal alone: at least watch, never drifting (needs breadth).
      expect(r.level, DriftLevel.watch);

      final few = <DriftSignal, List<DatedValue>>{};
      DigitalTwinService.addAssessments(few, [phq(12, 7), phq(2, 15)]);
      expect(sig(DigitalTwinService.compute(now: now, data: few), DriftSignal.phq9).therapistText,
          'PHQ-9: learning baseline: 1/2 results');
    });

    test('level thresholds and early-warning entry (never a clinical level)', () {
      final r = DigitalTwinService.compute(now: now, data: {
        DriftSignal.restingHr: series(64, 80),
        DriftSignal.sleep: series(7.2, 4.5, wobble: 0.3),
        DriftSignal.steps: series(8000, 2500, wobble: 500),
        DriftSignal.checkIn: series(70, 40, wobble: 4),
      });
      expect(r.level, DriftLevel.drifting);
      final w = r.toEarlyWarning()!;
      expect(w.source, contains('Digital Twin drift'));
      expect(w.flagged, isTrue);
      expect(r.explanations.first, isNot(contains('no data')));
      expect(DriftLevel.drifting.patientLabel, 'Some changes from your usual');
      expect(DriftLevel.watch.patientLabel, DriftLevel.drifting.patientLabel);
    });
  });

  group('input adapters', () {
    test('vitals_daily docs', () {
      final out = <DriftSignal, List<DatedValue>>{};
      DigitalTwinService.addVitalsDaily(out, [
        {'date': '2026-11-16', 'hrRestingEstimate': 61, 'sleepHours': 7.5, 'steps': 9000},
        {'date': '2026-11-15', 'hrRestingEstimate': null, 'sleepHours': 6.0},
        {'date': 'bad', 'steps': 1},
      ]);
      expect(out[DriftSignal.restingHr]!.length, 1);
      expect(out[DriftSignal.sleep]!.length, 2);
      expect(out[DriftSignal.steps]!.single.day, DateTime(2026, 11, 16));
    });

    test('daily logs: wellbeing, else 100 - riskScore, else nothing', () {
      final out = <DriftSignal, List<DatedValue>>{};
      DigitalTwinService.addDailyLogs(out, [
        (at: daysAgo(1), wellbeing: 80, riskScore: 20),
        (at: daysAgo(2), wellbeing: null, riskScore: 30),
        (at: daysAgo(3), wellbeing: null, riskScore: null),
      ]);
      expect(out[DriftSignal.checkIn]!.map((v) => v.value), [80, 70]);
    });
  });
}
