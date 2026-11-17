import 'package:flutter_test/flutter_test.dart';
import 'package:mindtwin/services/session_brief_service.dart';

void main() {
  final json = <String, dynamic>{
    'brief': {
      'generatedAt': '2026-11-17T12:00:00.000Z',
      'period': {
        'from': '2026-11-01T09:00:00.000Z',
        'to': '2026-11-17T12:00:00.000Z',
        'basis': 'last_completed_session',
      },
      'sections': [
        {
          'title': 'Instruments (PHQ-9, GAD-7, C-SSRS)',
          'items': [
            {
              'text': 'PHQ-9 rose from 11 to 17 (Nov 2 → Nov 15).',
              'source': {
                'collection': 'clinical_assessments',
                'docId': 'a1',
                'field': 'totalScore',
                'at': '2026-11-15T10:00:00.000Z',
              },
            },
            {'text': '', 'source': {}},
          ],
        },
        {'title': 'Journal entries shared with you', 'items': []},
      ],
      'flags': [
        {
          'text': 'Unacknowledged: C-SSRS moderate-risk alert',
          'source': {'collection': 'crisis_events', 'docId': 'e1', 'field': 'acknowledged', 'at': null},
        },
      ],
      'dataGaps': ['No wearable vitals in this period.', 3],
    },
    'narrative': null,
    'narrativeReason': 'no_patient_consent',
  };

  test('parses the backend response defensively', () {
    final b = SessionBrief.fromJson(json);
    expect(b.basis, 'last_completed_session');
    expect(b.sections, hasLength(2));
    expect(b.sections.first.items, hasLength(1)); // empty item dropped
    final src = b.sections.first.items.first.source;
    expect(src.typeLabel, 'Assessment');
    expect(src.at, isNotNull);
    expect(b.flags.single.source.at, isNull);
    expect(b.dataGaps, ['No wearable vitals in this period.']);
    expect(b.narrative, isNull);
    expect(b.narrativeReason, 'no_patient_consent');
  });

  test('plain-text export has the footer and no ids', () {
    final text = SessionBrief.fromJson(json).toPlainText(periodLabel: 'since last session');
    expect(text, contains('PHQ-9 rose from 11 to 17'));
    expect(text, contains('Flags'));
    expect(text, contains('Decision support only. Not a diagnosis or prescription.'));
    expect(text, isNot(contains('a1')));
    expect(text, isNot(contains('AI narrative')));
  });

  test('includes the AI narrative with its label when present', () {
    final withNarrative = Map<String, dynamic>.from(json)..['narrative'] = 'PHQ-9 rose.';
    final text = SessionBrief.fromJson(withNarrative).toPlainText();
    expect(text, contains('AI narrative (consented, de-identified'));
  });
}
