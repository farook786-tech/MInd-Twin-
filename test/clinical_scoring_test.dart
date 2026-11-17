import 'package:flutter_test/flutter_test.dart';
import 'package:mindtwin/services/clinical_scoring.dart';

void main() {
  final now = DateTime.utc(2026, 11, 17, 12);

  group('PHQ-9 bands (Kroenke 2001)', () {
    test('band boundaries 0-4/5-9/10-14/15-19/20-27', () {
      const expected = {
        0: 'minimal', 4: 'minimal', 5: 'mild', 9: 'mild', 10: 'moderate', 14: 'moderate',
        15: 'moderately_severe', 19: 'moderately_severe', 20: 'severe', 27: 'severe',
      };
      expected.forEach((total, band) => expect(ClinicalScoring.phq9Band(total), band, reason: '$total'));
    });
    test('scorePhq9 sums items and keeps item 9', () {
      final s = ClinicalScoring.scorePhq9([3, 3, 2, 2, 2, 2, 2, 1, 1]);
      expect(s.total, 18);
      expect(s.band, 'moderately_severe');
      expect(s.bandLabel, 'moderately severe');
      expect(s.item9, 1);
      expect(s.maxTotal, 27);
    });
    test('rejects incomplete or out-of-range answers', () {
      expect(() => ClinicalScoring.scorePhq9([1, 1, 1]), throwsArgumentError);
      expect(() => ClinicalScoring.scorePhq9([0, 0, 0, 0, 0, 0, 0, 0, 4]), throwsArgumentError);
      expect(() => ClinicalScoring.scorePhq9([0, 0, 0, 0, 0, 0, 0, 0, -1]), throwsArgumentError);
    });
  });

  group('GAD-7 bands (Spitzer 2006)', () {
    test('band boundaries 0-4/5-9/10-14/15-21', () {
      const expected = {0: 'minimal', 4: 'minimal', 5: 'mild', 9: 'mild', 10: 'moderate', 14: 'moderate', 15: 'severe', 21: 'severe'};
      expected.forEach((total, band) => expect(ClinicalScoring.gad7Band(total), band, reason: '$total'));
    });
    test('scoreGad7', () {
      final s = ClinicalScoring.scoreGad7([3, 3, 3, 3, 3, 3, 3]);
      expect(s.total, 21);
      expect(s.band, 'severe');
      expect(s.item9, isNull);
      expect(() => ClinicalScoring.scoreGad7([1, 1]), throwsArgumentError);
    });
  });

  group('C-SSRS screener triage (Columbia, Screen Version - Recent)', () {
    CssrsRisk triage({
      bool q1 = false,
      bool q2 = false,
      bool? q3,
      bool? q4,
      bool? q5,
      bool q6 = false,
      bool? q6Recent,
    }) =>
        ClinicalScoring.triageCssrs(
            CssrsAnswers(q1: q1, q2: q2, q3: q3, q4: q4, q5: q5, q6: q6, q6Recent: q6Recent)).risk;

    test('all no => none', () => expect(triage(), CssrsRisk.none));
    test('Q1 only => low', () => expect(triage(q1: true), CssrsRisk.low));
    test('Q2 yes, Q3-5 no => low', () => expect(triage(q1: true, q2: true, q3: false, q4: false, q5: false), CssrsRisk.low));
    test('Q3 yes => moderate', () => expect(triage(q2: true, q3: true, q4: false, q5: false), CssrsRisk.moderate));
    test('Q6 yes > 3 months ago => moderate', () => expect(triage(q6: true, q6Recent: false), CssrsRisk.moderate));
    test('Q4 yes => high', () => expect(triage(q2: true, q3: false, q4: true, q5: false), CssrsRisk.high));
    test('Q5 yes => high', () => expect(triage(q2: true, q3: true, q4: false, q5: true), CssrsRisk.high));
    test('Q6 yes within 3 months => high', () => expect(triage(q6: true, q6Recent: true), CssrsRisk.high));
    test('Q6 yes with unknown recency fails safe to high', () => expect(triage(q6: true), CssrsRisk.high));
    test('Q6 lifetime + Q4 => high (most severe wins)',
        () => expect(triage(q2: true, q3: true, q4: true, q5: false, q6: true, q6Recent: false), CssrsRisk.high));

    test('positive items are explainable', () {
      final t = ClinicalScoring.triageCssrs(const CssrsAnswers(
          q1: true, q2: true, q3: true, q4: true, q5: false, q6: true, q6Recent: false));
      expect(t.positiveItems, ['q1', 'q2', 'q3', 'q4', 'q6_lifetime']);
      expect(ClinicalScoring.cssrsItemLabel('q4'), 'C-SSRS Q4 = yes (intent)');
    });

    test('skip logic: Q2 no skips Q3-Q5; Q6 yes asks recency', () {
      expect(ClinicalScoring.nextCssrsQuestion({}), 'q1');
      expect(ClinicalScoring.nextCssrsQuestion({'q1': true}), 'q2');
      expect(ClinicalScoring.nextCssrsQuestion({'q1': true, 'q2': false}), 'q6');
      expect(ClinicalScoring.nextCssrsQuestion({'q1': false, 'q2': true}), 'q3');
      expect(ClinicalScoring.nextCssrsQuestion({'q1': false, 'q2': true, 'q3': false}), 'q4');
      expect(ClinicalScoring.nextCssrsQuestion({'q1': false, 'q2': true, 'q3': false, 'q4': false}), 'q5');
      expect(ClinicalScoring.nextCssrsQuestion({'q1': false, 'q2': true, 'q3': false, 'q4': false, 'q5': false}), 'q6');
      expect(ClinicalScoring.nextCssrsQuestion({'q1': false, 'q2': false, 'q6': false}), isNull);
      expect(ClinicalScoring.nextCssrsQuestion({'q1': false, 'q2': false, 'q6': true}), 'q6Recent');
      expect(ClinicalScoring.nextCssrsQuestion({'q1': false, 'q2': false, 'q6': true, 'q6Recent': true}), isNull);
    });

    test('Firestore shape nulls skipped items; completeness check', () {
      final a = CssrsAnswers.fromAnswered({'q1': true, 'q2': false, 'q6': false});
      expect(a.toFirestore(), {'q1': true, 'q2': false, 'q3': null, 'q4': null, 'q5': null, 'q6': false, 'q6Recent': null});
      expect(a.isComplete, isTrue);
      expect(const CssrsAnswers(q1: false, q2: true, q6: false).isComplete, isFalse);
      expect(const CssrsAnswers(q1: false, q2: false, q6: true).isComplete, isFalse);
      expect(CssrsAnswers.fromMap({'q1': true}), isNull);
      expect(CssrsAnswers.fromMap(a.toFirestore())!.q1, isTrue);
    });
  });

  group('combined clinical status', () {
    AssessmentRecord phq(String id, List<int> items, DateTime at, {List<int>? gad}) => AssessmentRecord.fromMap(id, {
          'type': 'phq9_gad7',
          'phq9Answers': items,
          'totalScore': items.fold<int>(0, (a, b) => a + b),
          'item9': items[8],
          if (gad != null) 'gad7Answers': gad,
          if (gad != null) 'gad7Score': gad.fold<int>(0, (a, b) => a + b),
          'timestamp': at,
        });
    AssessmentRecord cssrs(String id, Map<String, bool> answered, DateTime at, {String? storedRisk}) {
      final a = CssrsAnswers.fromAnswered(answered);
      return AssessmentRecord.fromMap(id, {
        'type': 'cssrs',
        'cssrsAnswers': a.toFirestore(),
        'cssrsRisk': storedRisk ?? ClinicalScoring.triageCssrs(a).risk.name,
        'timestamp': at,
      });
    }

    test('no data => none, says so, asks for instruments', () {
      final s = ClinicalScoring.computeStatus(assessments: const [], now: now);
      expect(s.level, ClinicalLevel.none);
      expect(s.hasInstrumentData, isFalse);
      expect(s.recommendedAction, contains('administer PHQ-9, GAD-7 and C-SSRS'));
      expect(s.reasons, isEmpty);
    });

    test('PHQ-9 18 three days ago => moderate with explainable reason', () {
      final s = ClinicalScoring.computeStatus(
        assessments: [phq('a1', [3, 3, 2, 2, 2, 2, 2, 2, 0], now.subtract(const Duration(days: 3)), gad: [1, 1, 1, 1, 1, 0, 0])],
        now: now,
      );
      expect(s.level, ClinicalLevel.moderate);
      expect(s.primaryDriver, 'PHQ-9');
      expect(s.reasons.first, 'PHQ-9 = 18 (moderately severe), 3 days ago');
      expect(s.reasons, contains('GAD-7 = 5 (mild), 3 days ago'));
      expect(s.recommendedAction, 'Schedule review within 1 week');
      expect(s.instrumentDates['phq9'], now.subtract(const Duration(days: 3)));
      expect(s.instrumentDates['cssrs'], isNull);
    });

    test('PHQ-9 item 9 > 0 without C-SSRS follow-up => high', () {
      final s = ClinicalScoring.computeStatus(
        assessments: [phq('a1', [0, 0, 0, 0, 0, 0, 0, 0, 1], now.subtract(const Duration(hours: 1)))],
        now: now,
      );
      expect(s.level, ClinicalLevel.high);
      expect(s.primaryDriver, 'PHQ-9 item 9');
      expect(s.reasons.first, contains('PHQ-9 item 9 = 1'));
      expect(s.reasons.first, contains('no C-SSRS follow-up yet'));
      expect(s.recommendedAction, 'Contact patient today');
    });

    test('C-SSRS Q4 yes => critical, item listed with age', () {
      final s = ClinicalScoring.computeStatus(
        assessments: [
          cssrs('c1', {'q1': true, 'q2': true, 'q3': false, 'q4': true, 'q5': false, 'q6': false},
              now.subtract(const Duration(hours: 2))),
          phq('a1', [1, 1, 1, 1, 1, 1, 1, 1, 2], now.subtract(const Duration(hours: 3))),
        ],
        now: now,
      );
      expect(s.level, ClinicalLevel.critical);
      expect(s.primaryDriver, 'C-SSRS');
      expect(s.recommendedAction, 'Immediate safety assessment');
      expect(s.reasons.first, startsWith('C-SSRS HIGH risk'));
      expect(s.reasons, contains('  • C-SSRS Q4 = yes (intent) — 2 h ago'));
      // item 9 still listed, but with the follow-up noted.
      expect(s.reasons.any((r) => r.contains('C-SSRS follow-up completed')), isTrue);
    });

    test('older C-SSRS HIGH stays visible until acknowledged, even after a negative screener', () {
      final old = cssrs('old', {'q1': true, 'q2': true, 'q3': true, 'q4': false, 'q5': true, 'q6': false},
          now.subtract(const Duration(days: 30)));
      final recent = cssrs('new', {'q1': false, 'q2': false, 'q6': false}, now.subtract(const Duration(days: 1)));
      final unacked = ClinicalScoring.computeStatus(
        assessments: [recent, old],
        unacknowledgedCrisis: const [CrisisRecord(id: 'assessment_old', eventType: 'cssrs_high', severity: 'critical')],
        now: now,
      );
      expect(unacked.level, ClinicalLevel.critical);
      expect(unacked.reasons.any((r) => r.contains('alert not yet acknowledged')), isTrue);
      expect(unacked.reasons.any((r) => r.contains('STALE')), isTrue, reason: 'labelled stale, not dropped');

      final acked = ClinicalScoring.computeStatus(assessments: [recent, old], now: now);
      expect(acked.level, ClinicalLevel.none);
      expect(acked.hasInstrumentData, isTrue);
    });

    test('unacknowledged cssrs_high whose assessment is outside the window still shows', () {
      final s = ClinicalScoring.computeStatus(
        assessments: const [],
        unacknowledgedCrisis: [
          CrisisRecord(id: 'assessment_zz', eventType: 'cssrs_high', at: now.subtract(const Duration(days: 40))),
        ],
        now: now,
      );
      expect(s.level, ClinicalLevel.critical);
    });

    test('stored risk more severe than recomputed wins (fail safe)', () {
      final s = ClinicalScoring.computeStatus(
        assessments: [cssrs('c', {'q1': true, 'q2': false, 'q6': false}, now, storedRisk: 'high')],
        now: now,
      );
      expect(s.level, ClinicalLevel.critical);
    });

    test('C-SSRS moderate (lifetime behaviour) => high; low => moderate', () {
      expect(
        ClinicalScoring.computeStatus(
          assessments: [cssrs('c', {'q1': false, 'q2': false, 'q6': true, 'q6Recent': false}, now)],
          now: now,
        ).level,
        ClinicalLevel.high,
      );
      expect(
        ClinicalScoring.computeStatus(
          assessments: [cssrs('c', {'q1': true, 'q2': false, 'q6': false}, now)],
          now: now,
        ).level,
        ClinicalLevel.moderate,
      );
    });

    test('stale instruments are labelled and re-administration is asked; level kept', () {
      final s = ClinicalScoring.computeStatus(
        assessments: [phq('a1', [3, 3, 3, 3, 3, 3, 2, 0, 0], now.subtract(const Duration(days: 20)))],
        now: now,
      );
      expect(s.level, ClinicalLevel.high, reason: 'PHQ-9 20 severe still counts');
      expect(s.staleInstruments, ['PHQ-9']);
      expect(s.reasons.first, contains('STALE'));
      expect(s.recommendedAction, contains('re-administer PHQ-9'));
    });

    test('early warnings never change the level but are listed and prompt re-assessment', () {
      final warnings = earlyWarningsFromSnapshot(checkInIndicator: 88, checkInAt: now, heartRate: 140, heartRateAt: now);
      final s = ClinicalScoring.computeStatus(
        assessments: [phq('a1', [0, 0, 0, 0, 0, 0, 0, 0, 0], now)],
        earlyWarnings: warnings,
        unacknowledgedCrisis: const [CrisisRecord(id: 'x', eventType: 'chat_crisis', title: 'Crisis language')],
        now: now,
      );
      expect(s.level, ClinicalLevel.none);
      expect(s.earlyWarnings.length, 3);
      expect(s.earlyWarnings.first.source, 'Check-in wellbeing indicator');
      expect(s.earlyWarnings.first.detail, contains('88/100'));
      expect(s.recommendedAction, contains('review early-warning signals'));
    });

    test('missing early-warning data produces no entries', () {
      expect(earlyWarningsFromSnapshot(), isEmpty);
      expect(earlyWarningsFromSnapshot(checkInIndicator: double.nan), isEmpty);
    });

    test('sparkline history: last 8, oldest first', () {
      final list = [
        for (var i = 0; i < 10; i++)
          phq('a$i', [i % 4, 0, 0, 0, 0, 0, 0, 0, 0], now.subtract(Duration(days: i))),
      ];
      final s = ClinicalScoring.computeStatus(assessments: list, now: now);
      expect(s.phq9History.length, 8);
      expect(s.phq9History.last, 0, reason: 'newest (i=0) last');
      expect(s.phq9History.first, 3, reason: 'i=7 -> 7 % 4');
    });

    test('legacy assessment shape (answers.phq9, phq9Score) is parsed', () {
      final r = AssessmentRecord.fromMap('l', {
        'phq9Score': 4,
        'answers': {'phq9': [0, 0, 0, 1, 1, 1, 1, 0, 2]},
        'timestamp': now,
      });
      expect(r.phq9Total, 6, reason: 'recomputed from items; most severe wins');
      expect(r.phq9Item9, 2);
    });

    test('never recommends medication', () {
      for (final l in ClinicalLevel.values) {
        expect(l.recommendedAction.toLowerCase(), isNot(matches(RegExp(r'medic|dose|prescri|mg\b'))));
      }
    });
  });

  group('roster level and cadence', () {
    test('rosterLevel uses snapshots and unacknowledged alerts', () {
      expect(ClinicalScoring.rosterLevel(), ClinicalLevel.none);
      expect(ClinicalScoring.rosterLevel(phq9Total: 21), ClinicalLevel.high);
      expect(ClinicalScoring.rosterLevel(gad7Total: 16), ClinicalLevel.moderate);
      expect(ClinicalScoring.rosterLevel(cssrsRisk: CssrsRisk.high), ClinicalLevel.critical);
      expect(ClinicalScoring.rosterLevel(phq9Total: 3, unacknowledgedEventTypes: ['cssrs_high']), ClinicalLevel.critical);
      expect(ClinicalScoring.rosterLevel(unacknowledgedEventTypes: ['phq9_severe']), ClinicalLevel.high);
      expect(ClinicalScoring.rosterLevel(unacknowledgedEventTypes: ['vital_high']), ClinicalLevel.none);
    });
    test('weekly C-SSRS prompt', () {
      expect(ClinicalScoring.isCssrsDue(null, now), isTrue);
      expect(ClinicalScoring.isCssrsDue(now.subtract(const Duration(days: 6)), now), isFalse);
      expect(ClinicalScoring.isCssrsDue(now.subtract(const Duration(days: 7)), now), isTrue);
    });
    test('describeAge', () {
      expect(ClinicalScoring.describeAge(now, now), 'just now');
      expect(ClinicalScoring.describeAge(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(ClinicalScoring.describeAge(now.subtract(const Duration(hours: 2)), now), '2 h ago');
      expect(ClinicalScoring.describeAge(now.subtract(const Duration(days: 1)), now), '1 day ago');
      expect(ClinicalScoring.describeAge(now.subtract(const Duration(days: 3)), now), '3 days ago');
    });
  });
}
