// Safety tests for risk scoring (MlRiskService), check-in scoring and anomaly
// detection (MlAnomalyService). Report: docs/ML_SAFETY_EVALUATION.md
import 'package:flutter_test/flutter_test.dart';
import 'package:mindtwin/models/daily_log.dart';
import 'package:mindtwin/services/ml_anomaly_service.dart';
import 'package:mindtwin/services/ml_risk_service.dart';

final DateTime now = DateTime(2026, 11, 17, 12);

DailyLog log(int daysAgo, {double mood = 7.5, double sleep = 8, double energy = 6.7, double anxiety = 5}) => DailyLog(
      id: 'l$daysAgo',
      patientId: 'p',
      timestamp: now.subtract(Duration(days: daysAgo)),
      moodScore: mood,
      sleepHours: sleep,
      energyLevel: energy,
      anxietyLevel: anxiety,
      wellbeingScore: 50,
    );

void main() {
  group('component risk: directions, units, monotonicity', () {
    const moods = [0.0, 2.5, 5.0, 7.5, 10.0];
    const energies = [0.0, 3.3, 6.7, 10.0];
    const sleeps = [0.0, 2.0, 4.0, 6.0, 7.0, 8.0, 9.0, 10.0, 12.0, 14.0, 16.0];

    test('higher mood/energy never increases risk; anxiety never decreases it', () {
      for (final s in sleeps) {
        for (final e in energies) {
          for (var i = 1; i < moods.length; i++) {
            expect(MlRiskService.componentRisk(mood0to10: moods[i], sleepHours: s, energy0to10: e)!,
                lessThanOrEqualTo(MlRiskService.componentRisk(mood0to10: moods[i - 1], sleepHours: s, energy0to10: e)!));
          }
        }
        for (final m in moods) {
          for (var i = 1; i < energies.length; i++) {
            expect(MlRiskService.componentRisk(mood0to10: m, sleepHours: s, energy0to10: energies[i])!,
                lessThanOrEqualTo(MlRiskService.componentRisk(mood0to10: m, sleepHours: s, energy0to10: energies[i - 1])!));
          }
        }
      }
      for (var a = 0.0; a < 10; a += 1) {
        expect(MlRiskService.componentRisk(mood0to10: 5, anxiety0to10: a + 1)!,
            greaterThanOrEqualTo(MlRiskService.componentRisk(mood0to10: 5, anxiety0to10: a)!));
      }
    });

    test('sleep is U-shaped: too little AND too much both raise risk', () {
      expect(MlRiskService.sleepRisk(8), 0);
      expect(MlRiskService.sleepRisk(3)!, greaterThan(MlRiskService.sleepRisk(6)!));
      expect(MlRiskService.sleepRisk(13)!, greaterThan(MlRiskService.sleepRisk(10)!));
      expect(MlRiskService.sleepRisk(10)!, greaterThan(0));
      for (var h = 0.0; h < 7; h += 0.5) {
        expect(MlRiskService.sleepRisk(h)!, greaterThanOrEqualTo(MlRiskService.sleepRisk(h + 0.5)!));
      }
      for (var h = 9.0; h < 16; h += 0.5) {
        expect(MlRiskService.sleepRisk(h + 0.5)!, greaterThanOrEqualTo(MlRiskService.sleepRisk(h)!));
      }
    });

    test('boundaries: best = 0, worst = 100, out-of-range clamps', () {
      expect(MlRiskService.componentRisk(mood0to10: 10, sleepHours: 8, energy0to10: 10, anxiety0to10: 0), 0);
      expect(MlRiskService.componentRisk(mood0to10: 0, sleepHours: 0, energy0to10: 0, anxiety0to10: 10), 100);
      expect(MlRiskService.componentRisk(mood0to10: -5, sleepHours: 30, energy0to10: 99), inInclusiveRange(0, 100));
    });

    test('NaN / null are dropped, never fabricated', () {
      expect(MlRiskService.componentRisk(), isNull);
      expect(MlRiskService.componentRisk(mood0to10: double.nan, sleepHours: double.nan), isNull);
      expect(MlRiskService.componentRisk(mood0to10: 0, sleepHours: double.nan), 100);
      expect(MlRiskService.sleepRisk(-1), isNull);
    });
  });

  group('computeRisk', () {
    test('no logs -> null (old code fabricated 35 "moderate")', () {
      expect(MlRiskService.computeRisk(const [], now: now), isNull);
    });

    test('anxiety default (5.0) is ignored unless recorded', () {
      final a = MlRiskService.computeRisk([log(0, anxiety: 5)], now: now)!;
      final b = MlRiskService.computeRisk([log(0, anxiety: 9)], now: now)!;
      expect(a.riskScore, b.riskScore);
    });

    test('worse latest day never lowers the score; one bad day is not averaged away', () {
      final good = List.generate(7, (i) => log(i));
      final base = MlRiskService.computeRisk(good, now: now)!.riskScore;
      final worse = MlRiskService.computeRisk([log(0, mood: 0, sleep: 2, energy: 0), ...good.skip(1)], now: now)!;
      expect(worse.riskScore, greaterThan(base + 20));
      expect(worse.keyFactors, contains('Latest check-in in critical range'));
    });

    test('order of input does not matter (sorted internally)', () {
      final logs = [log(3, mood: 0), log(0, mood: 10), log(1, mood: 5)];
      expect(MlRiskService.computeRisk(logs, now: now)!.riskScore,
          MlRiskService.computeRisk(logs.reversed.toList(), now: now)!.riskScore);
    });

    test('trend: worsening detected, stale data lowers confidence', () {
      final logs = [
        log(0, mood: 0, energy: 0), log(1, mood: 0, energy: 0), log(2, mood: 2.5, energy: 0),
        log(3), log(4), log(5), log(6),
      ];
      expect(MlRiskService.computeRisk(logs, now: now)!.trend, 'worsening');
      final fresh = MlRiskService.computeRisk([log(0), log(1)], now: now)!;
      final stale = MlRiskService.computeRisk([log(10), log(11)], now: now)!;
      expect(stale.confidence, lessThan(fresh.confidence));
      expect(stale.keyFactors.any((f) => f.startsWith('No check-in for')), isTrue);
    });

    test('risk bands', () {
      expect(MlRiskService.riskLevelFor(0), 'low');
      expect(MlRiskService.riskLevelFor(25), 'moderate');
      expect(MlRiskService.riskLevelFor(50), 'high');
      expect(MlRiskService.riskLevelFor(75), 'critical');
    });
  });

  group('daily check-in score (replacement for daily_checkin_screen._riskScoreFromInputs)', () {
    const moods = ['great', 'okay', 'frustrated', 'anxious', 'sad'];
    const sleeps = ['great', 'okay', 'poor', 'barely_slept'];
    const energies = ['high', 'normal', 'low', 'drained'];

    test('missing answers -> null, never "best"', () {
      expect(MlRiskService.checkInRiskScore(moodId: null, sleepId: 'great', energyId: 'high'), isNull);
      expect(MlRiskService.checkInRiskScore(moodId: 'sad', sleepId: null, energyId: 'high'), isNull);
      expect(MlRiskService.checkInRiskScore(moodId: 'unknown', sleepId: 'great', energyId: 'high'), isNull);
    });

    test('monotonic in every answer, range 0..100', () {
      for (final m in moods) {
        for (final s in sleeps) {
          for (final e in energies) {
            final v = MlRiskService.checkInRiskScore(moodId: m, sleepId: s, energyId: e)!;
            expect(v, inInclusiveRange(0, 100));
            final mi = moods.indexOf(m), si = sleeps.indexOf(s), ei = energies.indexOf(e);
            if (mi > 0) expect(v, greaterThanOrEqualTo(MlRiskService.checkInRiskScore(moodId: moods[mi - 1], sleepId: s, energyId: e)!));
            if (si > 0) expect(v, greaterThanOrEqualTo(MlRiskService.checkInRiskScore(moodId: m, sleepId: sleeps[si - 1], energyId: e)!));
            if (ei > 0) expect(v, greaterThanOrEqualTo(MlRiskService.checkInRiskScore(moodId: m, sleepId: s, energyId: energies[ei - 1])!));
          }
        }
      }
      expect(MlRiskService.checkInRiskScore(moodId: 'great', sleepId: 'great', energyId: 'high'), 0);
      expect(MlRiskService.checkInRiskScore(moodId: 'sad', sleepId: 'barely_slept', energyId: 'drained'), 100);
    });

    test('sad is never scored as lower risk than frustrated (old formula bug)', () {
      expect(MlRiskService.checkInRiskScore(moodId: 'sad', sleepId: 'okay', energyId: 'normal')!,
          greaterThan(MlRiskService.checkInRiskScore(moodId: 'frustrated', sleepId: 'okay', energyId: 'normal')!));
    });

    test('oversleeping scores above healthy sleep', () {
      expect(MlRiskService.checkInRiskScore(moodId: 'okay', sleepId: 'too_much', energyId: 'normal')!,
          greaterThan(MlRiskService.checkInRiskScore(moodId: 'okay', sleepId: 'great', energyId: 'normal')!));
    });

    test('safety prompt triggers beyond sad+drained+2 worries', () {
      expect(MlRiskService.checkInNeedsSafetyPrompt(moodId: 'sad', sleepId: 'barely_slept', energyId: 'normal'), isTrue);
      expect(MlRiskService.checkInNeedsSafetyPrompt(moodId: 'anxious', sleepId: 'okay', energyId: 'drained'), isTrue);
      expect(MlRiskService.checkInNeedsSafetyPrompt(moodId: 'great', riskScore: 80), isTrue);
      expect(MlRiskService.checkInNeedsSafetyPrompt(moodId: 'great', sleepId: 'great', energyId: 'high'), isFalse);
    });
  });

  group('anomaly detection', () {
    test('few data points: no deviation alarm, but critical day is still reported', () {
      final r = MlAnomalyService.detectFromLogs([log(0, mood: 5), log(1), log(2)], now: now);
      expect(r.anomalyDetected, isFalse);
      expect(r.anomalyType, 'insufficient_data');
      final crit = MlAnomalyService.detectFromLogs([log(0, mood: 0, sleep: 2, energy: 0)], now: now);
      expect(crit.anomalyDetected, isTrue);
      expect(crit.anomalyType, 'acute_high_risk');
    });

    test('one-step mood change on a stable baseline is not a false alarm', () {
      final logs = [log(0, mood: 5), ...List.generate(6, (i) => log(i + 1, mood: 7.5))];
      expect(MlAnomalyService.detectFromLogs(logs, now: now).anomalyDetected, isFalse);
    });

    test('large spike over a stable baseline is detected', () {
      final logs = [log(0, mood: 2.5, energy: 3.3, sleep: 4), ...List.generate(6, (i) => log(i + 1, mood: 10, energy: 10))];
      final r = MlAnomalyService.detectFromLogs(logs, now: now);
      expect(r.anomalyDetected, isTrue);
      expect(r.anomalyType, 'risk_spike');
    });

    test('missing days: old logs are not used as baseline; long silence is flagged', () {
      final gappy = [log(0, mood: 2.5), log(40), log(41), log(42), log(43), log(44)];
      expect(MlAnomalyService.detectFromLogs(gappy, now: now).anomalyType, 'insufficient_data');
      final silent = MlAnomalyService.detectFromLogs([log(9), log(10), log(11)], now: now);
      expect(silent.anomalyDetected, isTrue);
      expect(silent.anomalyType, 'missed_checkins');
    });

    test('no logs and NaN logs are safe', () {
      expect(MlAnomalyService.detectFromLogs(const [], now: now).anomalyDetected, isFalse);
      final nanLog = log(0, mood: double.nan, sleep: double.nan, energy: double.nan);
      expect(MlAnomalyService.detectFromLogs([nanLog], now: now).anomalyType, 'insufficient_data');
    });
  });
}
