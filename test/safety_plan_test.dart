import 'package:flutter_test/flutter_test.dart';
import 'package:mindtwin/models/safety_plan.dart';
import 'package:mindtwin/services/emergency_contacts.dart';

void main() {
  group('EmergencyContacts (India first)', () {
    test('India section lists Tele-MANAS and 112 first, no US defaults', () {
      final dials = EmergencyContacts.india.map((n) => n.dial).toList();
      expect(dials.first, '14416');
      expect(dials, containsAll(['14416', '112', '18008914416']));
      expect(dials, isNot(contains('988')));
      expect(dials, isNot(contains('911')));
    });

    test('international numbers only in the secondary section', () {
      final dials = EmergencyContacts.outsideIndia.map((n) => n.dial).toList();
      expect(dials, containsAll(['988', '911', '116123', '999']));
    });

    test('trusted contact SMS text matches the agreed wording', () {
      expect(EmergencyContacts.trustedContactSmsBody, "I'm not okay and need help. Please call me.");
    });
  });

  group('SafetyPlan', () {
    test('round-trips the Firestore shape', () {
      final plan = SafetyPlan.fromMap('p1', {
        'patientId': 'p1',
        'therapistId': 't1',
        'warningSigns': ['Not sleeping', ''],
        'copingStrategies': ['Walk'],
        'distractionsPeople': [
          {'name': 'Temple'},
        ],
        'helpContacts': [
          {'name': 'Asha'},
          {'name': 'Ravi', 'phone': '+91 98765 43210'},
        ],
        'professionals': [
          {'name': 'Tele-MANAS', 'phone': '14416'},
        ],
        'environmentSafety': 'Brother keeps my tablets',
        'reasonsToLive': ['My daughter'],
      });
      expect(plan.therapistId, 't1');
      expect(plan.warningSigns, ['Not sleeping']);
      expect(plan.isEmpty, isFalse);
      // First help contact WITH a phone is used for the SMS fallback.
      expect(plan.firstCallableHelpContact?.name, 'Ravi');

      final fields = plan.contentFields();
      expect(fields.keys.toSet(), {
        'warningSigns',
        'copingStrategies',
        'distractionsPeople',
        'helpContacts',
        'professionals',
        'environmentSafety',
        'reasonsToLive',
      });
      expect(fields['distractionsPeople'], [
        {'name': 'Temple'},
      ]);
      expect((fields['helpContacts'] as List)[1], {'name': 'Ravi', 'phone': '+91 98765 43210'});
    });

    test('empty / missing doc is an empty plan with no trusted contact', () {
      final plan = SafetyPlan.fromMap('p1', null);
      expect(plan.isEmpty, isTrue);
      expect(plan.firstCallableHelpContact, isNull);
    });

    test('contentFields enforces the rule limits', () {
      final plan = SafetyPlan(
        patientId: 'p1',
        warningSigns: List.generate(30, (i) => 'x' * 600),
        helpContacts: [SafetyPlanContact(name: 'n' * 150, phone: '9' * 40)],
        environmentSafety: 'e' * 3000,
      );
      final f = plan.contentFields();
      expect((f['warningSigns'] as List).length, SafetyPlan.maxItems);
      expect(((f['warningSigns'] as List).first as String).length, SafetyPlan.maxTextLength);
      final c = (f['helpContacts'] as List).first as Map;
      expect((c['name'] as String).length, SafetyPlan.maxNameLength);
      expect((c['phone'] as String).length, SafetyPlan.maxPhoneLength);
      expect((f['environmentSafety'] as String).length, SafetyPlan.maxEnvironmentLength);
    });
  });
}
