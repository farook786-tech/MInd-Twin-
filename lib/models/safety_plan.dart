import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A person in the safety plan (`{name, phone?}`).
@immutable
class SafetyPlanContact {
  final String name;
  final String? phone;

  const SafetyPlanContact({required this.name, this.phone});

  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'name': name.trim(),
        if (hasPhone) 'phone': phone!.trim(),
      };

  static SafetyPlanContact? fromValue(Object? v) {
    if (v is! Map) return null;
    final name = (v['name'] ?? '').toString().trim();
    final phone = v['phone']?.toString().trim();
    if (name.isEmpty && (phone == null || phone.isEmpty)) return null;
    return SafetyPlanContact(name: name, phone: (phone == null || phone.isEmpty) ? null : phone);
  }

  @override
  bool operator ==(Object other) =>
      other is SafetyPlanContact && other.name == name && other.phone == phone;

  @override
  int get hashCode => Object.hash(name, phone);
}

/// Stanley-Brown Safety Planning Intervention (Stanley B, Brown GK. Safety
/// Planning Intervention: a brief intervention to mitigate suicide risk.
/// Cogn Behav Pract 2012;19:256-264). Stored at `safety_plans/{patientId}`
/// (docs/DATA_MODEL.md). The seven steps, in order:
///  1. warning signs  2. internal coping strategies
///  3. people / social settings that provide distraction
///  4. people I can ask for help  5. professionals / agencies
///  6. making the environment safe  (+ reasons for living)
@immutable
class SafetyPlan {
  static const int maxItems = 20;
  static const int maxTextLength = 500;
  static const int maxNameLength = 100;
  static const int maxPhoneLength = 32;
  static const int maxEnvironmentLength = 2000;

  final String patientId;
  final String? therapistId;
  final List<String> warningSigns;
  final List<String> copingStrategies;
  final List<SafetyPlanContact> distractionsPeople;
  final List<SafetyPlanContact> helpContacts;
  final List<SafetyPlanContact> professionals;
  final String environmentSafety;
  final List<String> reasonsToLive;
  final DateTime? updatedAt;
  final String? updatedBy;

  const SafetyPlan({
    required this.patientId,
    this.therapistId,
    this.warningSigns = const [],
    this.copingStrategies = const [],
    this.distractionsPeople = const [],
    this.helpContacts = const [],
    this.professionals = const [],
    this.environmentSafety = '',
    this.reasonsToLive = const [],
    this.updatedAt,
    this.updatedBy,
  });

  factory SafetyPlan.empty(String patientId) => SafetyPlan(patientId: patientId);

  bool get isEmpty =>
      warningSigns.isEmpty &&
      copingStrategies.isEmpty &&
      distractionsPeople.isEmpty &&
      helpContacts.isEmpty &&
      professionals.isEmpty &&
      environmentSafety.trim().isEmpty &&
      reasonsToLive.isEmpty;

  /// First help contact that has a phone number (used for "Text my trusted
  /// contact"), or null.
  SafetyPlanContact? get firstCallableHelpContact {
    for (final c in helpContacts) {
      if (c.hasPhone) return c;
    }
    return null;
  }

  SafetyPlan copyWith({
    String? therapistId,
    List<String>? warningSigns,
    List<String>? copingStrategies,
    List<SafetyPlanContact>? distractionsPeople,
    List<SafetyPlanContact>? helpContacts,
    List<SafetyPlanContact>? professionals,
    String? environmentSafety,
    List<String>? reasonsToLive,
  }) {
    return SafetyPlan(
      patientId: patientId,
      therapistId: therapistId ?? this.therapistId,
      warningSigns: warningSigns ?? this.warningSigns,
      copingStrategies: copingStrategies ?? this.copingStrategies,
      distractionsPeople: distractionsPeople ?? this.distractionsPeople,
      helpContacts: helpContacts ?? this.helpContacts,
      professionals: professionals ?? this.professionals,
      environmentSafety: environmentSafety ?? this.environmentSafety,
      reasonsToLive: reasonsToLive ?? this.reasonsToLive,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );
  }

  static List<String> _cleanStrings(List<String> v) => v
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => s.length > maxTextLength ? s.substring(0, maxTextLength) : s)
      .take(maxItems)
      .toList();

  static List<Map<String, dynamic>> _cleanContacts(List<SafetyPlanContact> v) => v
      .where((c) => c.name.trim().isNotEmpty || c.hasPhone)
      .take(maxItems)
      .map((c) {
        var name = c.name.trim();
        if (name.isEmpty) name = 'Contact';
        if (name.length > maxNameLength) name = name.substring(0, maxNameLength);
        var phone = c.phone?.trim();
        if (phone != null && phone.length > maxPhoneLength) phone = phone.substring(0, maxPhoneLength);
        return SafetyPlanContact(name: name, phone: phone).toMap();
      })
      .toList();

  String get _cleanEnvironment {
    final t = environmentSafety.trim();
    return t.length > maxEnvironmentLength ? t.substring(0, maxEnvironmentLength) : t;
  }

  /// The editable plan fields (the only keys a therapist may change).
  Map<String, dynamic> contentFields() => {
        'warningSigns': _cleanStrings(warningSigns),
        'copingStrategies': _cleanStrings(copingStrategies),
        'distractionsPeople': _cleanContacts(distractionsPeople),
        'helpContacts': _cleanContacts(helpContacts),
        'professionals': _cleanContacts(professionals),
        'environmentSafety': _cleanEnvironment,
        'reasonsToLive': _cleanStrings(reasonsToLive),
      };

  static List<String> _strings(Object? v) =>
      v is List ? v.map((e) => e?.toString() ?? '').where((s) => s.trim().isNotEmpty).toList() : const [];

  static List<SafetyPlanContact> _contacts(Object? v) => v is List
      ? v.map(SafetyPlanContact.fromValue).whereType<SafetyPlanContact>().toList()
      : const [];

  factory SafetyPlan.fromMap(String patientId, Map<String, dynamic>? d) {
    if (d == null) return SafetyPlan.empty(patientId);
    final t = d['therapistId'];
    final at = d['updatedAt'];
    return SafetyPlan(
      patientId: patientId,
      therapistId: t is String && t.isNotEmpty ? t : null,
      warningSigns: _strings(d['warningSigns']),
      copingStrategies: _strings(d['copingStrategies']),
      distractionsPeople: _contacts(d['distractionsPeople']),
      helpContacts: _contacts(d['helpContacts']),
      professionals: _contacts(d['professionals']),
      environmentSafety: (d['environmentSafety'] ?? '').toString(),
      reasonsToLive: _strings(d['reasonsToLive']),
      updatedAt: at is Timestamp ? at.toDate() : null,
      updatedBy: d['updatedBy']?.toString(),
    );
  }
}
