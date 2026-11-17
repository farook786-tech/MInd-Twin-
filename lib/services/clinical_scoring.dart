// Pure clinical scoring and triage for MindTwin. No Flutter, no Firebase:
// everything here is deterministic and unit-tested (test/clinical_scoring_test.dart).
//
// DECISION SUPPORT ONLY. Nothing in this file diagnoses, rules out, or manages
// suicide risk, and nothing here recommends a medication or dose. The output
// tells a licensed clinician WHICH answers were given and WHICH clinical
// workflow step the published triage rules suggest. See
// docs/CLINICAL_SAFETY_CASE.md.
//
// Instruments and sources
// -----------------------
// * PHQ-9 — Kroenke K, Spitzer RL, Williams JBW. The PHQ-9: validity of a brief
//   depression severity measure. J Gen Intern Med 2001;16(9):606-613.
//   Severity bands 0-4 minimal, 5-9 mild, 10-14 moderate, 15-19 moderately
//   severe, 20-27 severe. Item 9 (thoughts that you would be better off dead
//   or of hurting yourself) is reviewed on its own whatever the total.
// * GAD-7 — Spitzer RL, Kroenke K, Williams JBW, Löwe B. A brief measure for
//   assessing generalized anxiety disorder: the GAD-7. Arch Intern Med
//   2006;166(10):1092-1097. Bands 0-4 minimal, 5-9 mild, 10-14 moderate,
//   15-21 severe.
// * C-SSRS Screener — Columbia-Suicide Severity Rating Scale, "Screen Version –
//   Recent" (Posner K, Brown GK, Stanley B, et al. Am J Psychiatry
//   2011;168(12):1266-1277; The Columbia Lighthouse Project,
//   https://cssrs.columbia.edu). Free for clinical use. Q1-Q5 refer to the past
//   month; Q6 asks about suicidal behaviour ever, and if yes whether it was in
//   the past 3 months. Published triage (screener colour coding):
//     - YES to Q1 or Q2 only                      -> LOW risk (offer resources)
//     - YES to Q3, or Q6 yes but > 3 months ago   -> MODERATE (clinician review soon)
//     - YES to Q4 or Q5, or Q6 yes in past 3 mo.  -> HIGH (immediate safety assessment)
//   Skip logic: Q3-Q5 are asked only if Q2 = yes; the 3-month follow-up only
//   if Q6 = yes. Mirrored server-side in functions/src/logic/cssrs.js.

/// Combined clinical status level shown to the therapist.
enum ClinicalLevel { none, low, moderate, high, critical }

extension ClinicalLevelX on ClinicalLevel {
  int get rank => index;
  String get label => name[0].toUpperCase() + name.substring(1);

  /// Clinical WORKFLOW step only (never a treatment or medication).
  String get recommendedAction {
    switch (this) {
      case ClinicalLevel.critical:
        return 'Immediate safety assessment';
      case ClinicalLevel.high:
        return 'Contact patient today';
      case ClinicalLevel.moderate:
        return 'Schedule review within 1 week';
      case ClinicalLevel.low:
        return 'Review at next scheduled session';
      case ClinicalLevel.none:
        return 'Continue routine monitoring';
    }
  }

  static ClinicalLevel parse(Object? v) {
    for (final l in ClinicalLevel.values) {
      if (l.name == v) return l;
    }
    return ClinicalLevel.none;
  }
}

ClinicalLevel maxLevel(ClinicalLevel a, ClinicalLevel b) => a.rank >= b.rank ? a : b;

// ---------------------------------------------------------------------------
// PHQ-9 / GAD-7
// ---------------------------------------------------------------------------

class InstrumentScore {
  final int total;
  final int maxTotal;

  /// Machine key, e.g. `moderately_severe` (the value stored in Firestore).
  final String band;

  /// PHQ-9 item 9 (0-3); null for GAD-7.
  final int? item9;

  const InstrumentScore({required this.total, required this.maxTotal, required this.band, this.item9});

  /// Human label, e.g. `moderately severe`.
  String get bandLabel => band.replaceAll('_', ' ');
}

class ClinicalScoring {
  ClinicalScoring._();

  static const int phq9Items = 9;
  static const int gad7Items = 7;

  /// An instrument older than this is labelled STALE (never silently dropped).
  static const Duration staleAfter = Duration(days: 14);

  /// Weekly C-SSRS cadence for the patient prompt.
  static const Duration cssrsCadence = Duration(days: 7);

  static String phq9Band(int total) {
    if (total >= 20) return 'severe';
    if (total >= 15) return 'moderately_severe';
    if (total >= 10) return 'moderate';
    if (total >= 5) return 'mild';
    return 'minimal';
  }

  static String gad7Band(int total) {
    if (total >= 15) return 'severe';
    if (total >= 10) return 'moderate';
    if (total >= 5) return 'mild';
    return 'minimal';
  }

  /// Scores 9 PHQ-9 answers (each 0-3). Throws [ArgumentError] on bad input:
  /// a partially answered PHQ-9 must never be shown as a valid total.
  static InstrumentScore scorePhq9(List<int> answers) {
    _validate(answers, phq9Items, 'PHQ-9');
    final total = answers.fold<int>(0, (a, b) => a + b);
    return InstrumentScore(total: total, maxTotal: 27, band: phq9Band(total), item9: answers[8]);
  }

  static InstrumentScore scoreGad7(List<int> answers) {
    _validate(answers, gad7Items, 'GAD-7');
    final total = answers.fold<int>(0, (a, b) => a + b);
    return InstrumentScore(total: total, maxTotal: 21, band: gad7Band(total));
  }

  static void _validate(List<int> answers, int n, String name) {
    if (answers.length != n) {
      throw ArgumentError('$name needs exactly $n answers, got ${answers.length}');
    }
    for (final a in answers) {
      if (a < 0 || a > 3) throw ArgumentError('$name answers must be 0-3, got $a');
    }
  }

  /// Contribution of a PHQ-9 total to the combined level (documented in
  /// docs/CLINICAL_SAFETY_CASE.md §4).
  static ClinicalLevel levelForPhq9Total(int total) {
    if (total >= 20) return ClinicalLevel.high;
    if (total >= 15) return ClinicalLevel.moderate;
    if (total >= 10) return ClinicalLevel.low;
    return ClinicalLevel.none;
  }

  static ClinicalLevel levelForGad7Total(int total) {
    if (total >= 15) return ClinicalLevel.moderate;
    if (total >= 10) return ClinicalLevel.low;
    return ClinicalLevel.none;
  }

  /// Contribution of a C-SSRS triage result to the combined level. Columbia
  /// LOW (any ideation in the past month) is deliberately mapped one step up
  /// to `moderate` (review within a week): conservative by design.
  static ClinicalLevel levelForCssrs(CssrsRisk risk) {
    switch (risk) {
      case CssrsRisk.high:
        return ClinicalLevel.critical;
      case CssrsRisk.moderate:
        return ClinicalLevel.high;
      case CssrsRisk.low:
        return ClinicalLevel.moderate;
      case CssrsRisk.none:
        return ClinicalLevel.none;
    }
  }

  /// Whether the weekly C-SSRS prompt should be shown to the patient.
  static bool isCssrsDue(DateTime? lastCompletedAt, DateTime now) =>
      lastCompletedAt == null || now.difference(lastCompletedAt) >= cssrsCadence;

  // -------------------------------------------------------------------------
  // C-SSRS screener
  // -------------------------------------------------------------------------

  /// Columbia triage of a screener (see file header). Fail-safe: Q6 = yes with
  /// an unknown recency is treated as within the past 3 months (HIGH).
  static CssrsTriage triageCssrs(CssrsAnswers a) {
    final positives = <String>[];
    if (a.q1) positives.add('q1');
    if (a.q2) positives.add('q2');
    if (a.q3 == true) positives.add('q3');
    if (a.q4 == true) positives.add('q4');
    if (a.q5 == true) positives.add('q5');
    if (a.q6) positives.add(a.q6Recent == false ? 'q6_lifetime' : 'q6_recent');

    final CssrsRisk risk;
    if (a.q4 == true || a.q5 == true || (a.q6 && a.q6Recent != false)) {
      risk = CssrsRisk.high;
    } else if (a.q3 == true || (a.q6 && a.q6Recent == false)) {
      risk = CssrsRisk.moderate;
    } else if (a.q1 || a.q2) {
      risk = CssrsRisk.low;
    } else {
      risk = CssrsRisk.none;
    }
    return CssrsTriage(risk: risk, positiveItems: positives);
  }

  /// Next screener question id given the answers so far, or null when done.
  /// Implements the protocol skip logic: Q3-Q5 only if Q2 = yes; `q6Recent`
  /// only if Q6 = yes.
  static String? nextCssrsQuestion(Map<String, bool> answered) {
    if (!answered.containsKey('q1')) return 'q1';
    if (!answered.containsKey('q2')) return 'q2';
    if (answered['q2'] == true) {
      for (final q in const ['q3', 'q4', 'q5']) {
        if (!answered.containsKey(q)) return q;
      }
    }
    if (!answered.containsKey('q6')) return 'q6';
    if (answered['q6'] == true && !answered.containsKey('q6Recent')) return 'q6Recent';
    return null;
  }

  // -------------------------------------------------------------------------
  // Combined clinical status
  // -------------------------------------------------------------------------

  /// Builds the therapist-facing clinical status.
  ///
  /// [assessments] — `clinical_assessments` docs for ONE patient (any order).
  /// [unacknowledgedCrisis] — that patient's `crisis_events` with
  /// `acknowledged == false` (used to keep a positive C-SSRS HIGH visible
  /// until a therapist acknowledges, and as early-warning signals).
  /// [earlyWarnings] — check-in / ML / vitals signals (never change the level).
  static ClinicalStatus computeStatus({
    required List<AssessmentRecord> assessments,
    List<CrisisRecord> unacknowledgedCrisis = const [],
    List<EarlyWarning> earlyWarnings = const [],
    required DateTime now,
  }) {
    final sorted = [...assessments]..sort((a, b) => _cmpDesc(a.at, b.at));
    final phqs = sorted.where((a) => a.phq9Total != null).toList();
    final gads = sorted.where((a) => a.gad7Total != null).toList();
    final cssrsList = sorted.where((a) => a.cssrs != null || a.cssrsRiskStored != null).toList();

    final contributions = <_Contribution>[];
    final stale = <String>[];
    final dates = <String, DateTime?>{'phq9': null, 'gad7': null, 'cssrs': null};

    String when(DateTime? at) => at == null ? 'date pending sync' : describeAge(at, now);
    bool isStale(DateTime? at) => at != null && now.difference(at) > staleAfter;
    String staleTag(DateTime? at) =>
        isStale(at) ? ' — STALE (>${staleAfter.inDays} days old; re-administer)' : '';

    // --- C-SSRS: latest screener, plus any HIGH not yet acknowledged.
    final unackIds = {for (final c in unacknowledgedCrisis) c.id};
    final shownCssrsIds = <String>{};
    void addCssrs(AssessmentRecord r, {required bool pinnedUnacknowledged}) {
      if (!shownCssrsIds.add(r.id)) return;
      final triage = r.cssrs == null ? null : triageCssrs(r.cssrs!);
      // Fail safe: the more severe of the recomputed and the stored risk.
      final risk = _maxCssrs(triage?.risk, r.cssrsRiskStored);
      final level = levelForCssrs(risk);
      final items = triage?.positiveItems ?? const <String>[];
      final ack = pinnedUnacknowledged ? ' (alert not yet acknowledged)' : '';
      if (risk == CssrsRisk.none) {
        contributions.add(_Contribution(level, 'C-SSRS screener negative (all answers no), ${when(r.at)}${staleTag(r.at)}',
            'C-SSRS', r.at));
        return;
      }
      final header = 'C-SSRS ${risk.name.toUpperCase()} risk (Columbia triage), ${when(r.at)}$ack${staleTag(r.at)}';
      contributions.add(_Contribution(level, header, 'C-SSRS', r.at));
      for (final item in items) {
        contributions.add(_Contribution(
          level,
          '  • ${cssrsItemLabel(item)} — ${when(r.at)}',
          'C-SSRS',
          r.at,
          detailOnly: true,
        ));
      }
      if (isStale(r.at)) stale.add('C-SSRS');
    }

    if (cssrsList.isNotEmpty) {
      dates['cssrs'] = cssrsList.first.at;
      addCssrs(cssrsList.first, pinnedUnacknowledged: unackIds.contains('assessment_${cssrsList.first.id}'));
    }
    for (final r in cssrsList.skip(1)) {
      final risk = _maxCssrs(r.cssrs == null ? null : triageCssrs(r.cssrs!).risk, r.cssrsRiskStored);
      if (risk == CssrsRisk.high && unackIds.contains('assessment_${r.id}')) {
        addCssrs(r, pinnedUnacknowledged: true);
      }
    }
    // Unacknowledged C-SSRS HIGH alerts whose assessment is not in the window.
    for (final c in unacknowledgedCrisis) {
      if (c.eventType != 'cssrs_high') continue;
      final aid = c.id.startsWith('assessment_') ? c.id.substring('assessment_'.length) : c.id;
      if (shownCssrsIds.contains(aid)) continue;
      shownCssrsIds.add(aid);
      contributions.add(_Contribution(
        ClinicalLevel.critical,
        'C-SSRS HIGH-risk alert, ${when(c.at)} (alert not yet acknowledged)',
        'C-SSRS',
        c.at,
      ));
    }

    // --- PHQ-9: latest total; item 9 reviewed on its own.
    if (phqs.isNotEmpty) {
      final p = phqs.first;
      dates['phq9'] = p.at;
      final total = p.phq9Total!;
      contributions.add(_Contribution(
        levelForPhq9Total(total),
        'PHQ-9 = $total (${phq9Band(total).replaceAll('_', ' ')}), ${when(p.at)}${staleTag(p.at)}',
        'PHQ-9',
        p.at,
      ));
      final item9 = p.phq9Item9;
      if (item9 != null && item9 > 0) {
        // A C-SSRS completed at/after this PHQ-9 is the specific follow-up;
        // item 9 then contributes `moderate` (still listed).
        final followUp = cssrsList.isNotEmpty &&
            cssrsList.first.at != null &&
            p.at != null &&
            !cssrsList.first.at!.isBefore(p.at!);
        contributions.add(_Contribution(
          followUp ? ClinicalLevel.moderate : ClinicalLevel.high,
          'PHQ-9 item 9 = $item9 (${_phqFrequency(item9)}: thoughts of being better off dead or of self-harm), '
          '${when(p.at)}${followUp ? ' — C-SSRS follow-up completed' : ' — no C-SSRS follow-up yet'}',
          'PHQ-9 item 9',
          p.at,
        ));
      }
      if (isStale(p.at)) stale.add('PHQ-9');
    }

    // --- GAD-7
    if (gads.isNotEmpty) {
      final g = gads.first;
      dates['gad7'] = g.at;
      final total = g.gad7Total!;
      contributions.add(_Contribution(
        levelForGad7Total(total),
        'GAD-7 = $total (${gad7Band(total)}), ${when(g.at)}${staleTag(g.at)}',
        'GAD-7',
        g.at,
      ));
      if (isStale(g.at)) stale.add('GAD-7');
    }

    // --- Level = most severe contribution.
    var level = ClinicalLevel.none;
    _Contribution? primary;
    for (final c in contributions) {
      if (c.detailOnly) continue;
      if (primary == null || c.level.rank > primary.level.rank) primary = c;
      level = maxLevel(level, c.level);
    }

    final hasInstrumentData = contributions.isNotEmpty;
    final reasons = <String>[];
    // Most severe first; item lines stay under their C-SSRS header.
    final headers = contributions.where((c) => !c.detailOnly).toList()
      ..sort((a, b) => b.level.rank.compareTo(a.level.rank));
    for (final h in headers) {
      reasons.add(h.text);
      if (h.driver == 'C-SSRS') {
        final idx = contributions.indexOf(h);
        for (var i = idx + 1; i < contributions.length && contributions[i].detailOnly; i++) {
          reasons.add(contributions[i].text);
        }
      }
    }

    String action;
    if (!hasInstrumentData) {
      action = 'No validated assessment on record: administer PHQ-9, GAD-7 and C-SSRS';
    } else {
      action = level.recommendedAction;
      if (stale.isNotEmpty) action += '; re-administer ${stale.join(', ')} (older than ${staleAfter.inDays} days)';
    }
    if (level.rank < ClinicalLevel.high.rank && earlyWarnings.any((w) => w.flagged)) {
      action += '; review early-warning signals and consider re-assessment with validated instruments';
    }

    final allWarnings = <EarlyWarning>[
      ...earlyWarnings,
      for (final c in unacknowledgedCrisis)
        if (_earlyWarningCrisisTypes.containsKey(c.eventType))
          EarlyWarning(
            source: _earlyWarningCrisisTypes[c.eventType]!,
            detail: '${c.title ?? 'Unacknowledged alert'} (unacknowledged)',
            at: c.at,
            flagged: true,
          ),
    ];

    List<int> history(List<AssessmentRecord> list, int? Function(AssessmentRecord) f) =>
        list.take(8).map(f).whereType<int>().toList().reversed.toList();

    return ClinicalStatus(
      level: level,
      hasInstrumentData: hasInstrumentData,
      primaryDriver: primary?.driver ?? 'No validated assessment on record',
      reasons: reasons,
      instrumentDates: dates,
      staleInstruments: stale,
      earlyWarnings: allWarnings,
      recommendedAction: action,
      phq9History: history(phqs, (a) => a.phq9Total),
      gad7History: history(gads, (a) => a.gad7Total),
    );
  }

  /// Roster level from the `users/{uid}` snapshot fields (`latestPhq9`,
  /// `latestGad7`, `latestCssrs`) plus unacknowledged crisis event types for
  /// that patient. Used to sort the therapist's patient list.
  static ClinicalLevel rosterLevel({
    int? phq9Total,
    int? gad7Total,
    CssrsRisk? cssrsRisk,
    Iterable<String> unacknowledgedEventTypes = const [],
  }) {
    var level = ClinicalLevel.none;
    if (phq9Total != null) level = maxLevel(level, levelForPhq9Total(phq9Total));
    if (gad7Total != null) level = maxLevel(level, levelForGad7Total(gad7Total));
    if (cssrsRisk != null) level = maxLevel(level, levelForCssrs(cssrsRisk));
    for (final t in unacknowledgedEventTypes) {
      if (t == 'cssrs_high') level = maxLevel(level, ClinicalLevel.critical);
      if (t == 'cssrs_moderate' || t == 'phq9_severe') level = maxLevel(level, ClinicalLevel.high);
    }
    return level;
  }

  /// "just now", "45 min ago", "2 h ago", "3 days ago".
  static String describeAge(DateTime at, DateTime now) {
    final d = now.difference(at);
    if (d.isNegative || d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    final days = d.inDays;
    return days == 1 ? '1 day ago' : '$days days ago';
  }

  static String cssrsItemLabel(String item) {
    switch (item) {
      case 'q1':
        return 'C-SSRS Q1 = yes (wish to be dead, past month)';
      case 'q2':
        return 'C-SSRS Q2 = yes (non-specific active suicidal thoughts, past month)';
      case 'q3':
        return 'C-SSRS Q3 = yes (thoughts of method, past month)';
      case 'q4':
        return 'C-SSRS Q4 = yes (intent)';
      case 'q5':
        return 'C-SSRS Q5 = yes (plan with intent)';
      case 'q6_recent':
        return 'C-SSRS Q6 = yes (suicidal behaviour, within past 3 months)';
      case 'q6_lifetime':
        return 'C-SSRS Q6 = yes (suicidal behaviour, lifetime, more than 3 months ago)';
    }
    return 'C-SSRS $item = yes';
  }

  static String _phqFrequency(int v) {
    switch (v) {
      case 1:
        return 'several days';
      case 2:
        return 'more than half the days';
      case 3:
        return 'nearly every day';
    }
    return 'not at all';
  }

  static const Map<String, String> _earlyWarningCrisisTypes = {
    'chat_crisis': 'Crisis language in chat (text classifier)',
    'checkin_crisis': 'Crisis language in check-in (text classifier)',
    'high_risk': 'Check-in wellbeing indicator',
    'vital_high': 'Wearable vital sign',
    'vital_low': 'Wearable vital sign',
    'sos': 'Patient pressed SOS',
  };

  static int _cmpDesc(DateTime? a, DateTime? b) {
    // Pending (null, not yet server-stamped) sorts as newest.
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return b.compareTo(a);
  }

  static CssrsRisk _maxCssrs(CssrsRisk? a, CssrsRisk? b) {
    final x = a ?? CssrsRisk.none;
    final y = b ?? CssrsRisk.none;
    return x.index >= y.index ? x : y;
  }
}

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

enum CssrsRisk { none, low, moderate, high }

CssrsRisk? parseCssrsRisk(Object? v) {
  for (final r in CssrsRisk.values) {
    if (r.name == v) return r;
  }
  return null;
}

/// C-SSRS Screener answers. Q3-Q5 are null when skipped (Q2 = no);
/// [q6Recent] is null when Q6 = no.
class CssrsAnswers {
  final bool q1;
  final bool q2;
  final bool? q3;
  final bool? q4;
  final bool? q5;
  final bool q6;
  final bool? q6Recent;

  const CssrsAnswers({
    required this.q1,
    required this.q2,
    this.q3,
    this.q4,
    this.q5,
    required this.q6,
    this.q6Recent,
  });

  /// From the screen's answer map (`q1`..`q6`, `q6Recent`).
  factory CssrsAnswers.fromAnswered(Map<String, bool> m) => CssrsAnswers(
        q1: m['q1'] ?? false,
        q2: m['q2'] ?? false,
        q3: m['q3'],
        q4: m['q4'],
        q5: m['q5'],
        q6: m['q6'] ?? false,
        q6Recent: m['q6Recent'],
      );

  /// Tolerant parse of a stored `cssrsAnswers` map; null if unusable.
  static CssrsAnswers? fromMap(Object? raw) {
    if (raw is! Map) return null;
    bool? b(String k) => raw[k] is bool ? raw[k] as bool : null;
    final q1 = b('q1'), q2 = b('q2'), q6 = b('q6');
    if (q1 == null || q2 == null || q6 == null) return null;
    return CssrsAnswers(q1: q1, q2: q2, q3: b('q3'), q4: b('q4'), q5: b('q5'), q6: q6, q6Recent: b('q6Recent'));
  }

  /// Exactly the Firestore `cssrsAnswers` shape (skipped items are null).
  Map<String, Object?> toFirestore() => {
        'q1': q1,
        'q2': q2,
        'q3': q2 ? q3 : null,
        'q4': q2 ? q4 : null,
        'q5': q2 ? q5 : null,
        'q6': q6,
        'q6Recent': q6 ? q6Recent : null,
      };

  /// True when the answers follow the protocol skip logic completely.
  bool get isComplete =>
      (q2 ? (q3 != null && q4 != null && q5 != null) : (q3 == null && q4 == null && q5 == null)) &&
      (q6 ? q6Recent != null : q6Recent == null);
}

class CssrsTriage {
  final CssrsRisk risk;

  /// Positive items: q1..q5, `q6_recent` or `q6_lifetime`.
  final List<String> positiveItems;

  const CssrsTriage({required this.risk, required this.positiveItems});
}

/// One `clinical_assessments` doc, normalised.
class AssessmentRecord {
  final String id;
  final String type;
  final DateTime? at;
  final int? phq9Total;
  final int? phq9Item9;
  final int? gad7Total;
  final CssrsAnswers? cssrs;
  final CssrsRisk? cssrsRiskStored;

  const AssessmentRecord({
    required this.id,
    this.type = '',
    this.at,
    this.phq9Total,
    this.phq9Item9,
    this.gad7Total,
    this.cssrs,
    this.cssrsRiskStored,
  });

  /// Parses the shapes written by phq9_assessment_screen.dart (current and
  /// legacy) and cssrs_screener_screen.dart. [toDate] converts a Firestore
  /// Timestamp (kept out of this pure file). Scores are recomputed from the
  /// item answers when present (most severe wins, as on the server).
  factory AssessmentRecord.fromMap(String id, Map<String, dynamic> d, {DateTime? Function(Object?)? toDate}) {
    DateTime? date(Object? v) {
      if (v is DateTime) return v;
      if (toDate != null) return toDate(v);
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    int? n(Object? v) => v is num && v.isFinite ? v.round() : null;
    List<int>? items(Object? v, int len) {
      if (v is! List || v.length != len) return null;
      final out = <int>[];
      for (final x in v) {
        final i = n(x);
        if (i == null || i < 0 || i > 3) return null;
        out.add(i);
      }
      return out;
    }

    final type = (d['type'] ?? '').toString();
    final isCssrs = type == 'cssrs';
    final answers = d['answers'] is Map ? d['answers'] as Map : const {};
    final phqItems = items(d['phq9Answers'], 9) ?? items(answers['phq9'], 9);
    final gadItems = items(d['gad7Answers'], 7) ?? items(answers['gad7'], 7);

    int? maxN(Iterable<int?> xs) {
      int? m;
      for (final x in xs) {
        if (x != null && (m == null || x > m)) m = x;
      }
      return m;
    }

    final phqTotal = isCssrs
        ? null
        : maxN([
            n(d['totalScore']),
            n(d['phq9Score']),
            phqItems?.fold<int>(0, (a, b) => a + b),
          ]);
    final gadTotal = isCssrs ? null : maxN([n(d['gad7Score']), gadItems?.fold<int>(0, (a, b) => a + b)]);
    return AssessmentRecord(
      id: id,
      type: type,
      at: date(d['timestamp']) ?? date(d['clientCreatedAt']),
      phq9Total: phqTotal?.clamp(0, 27),
      phq9Item9: isCssrs ? null : maxN([n(d['item9']), phqItems?[8]]),
      gad7Total: gadTotal?.clamp(0, 21),
      cssrs: isCssrs ? CssrsAnswers.fromMap(d['cssrsAnswers']) : null,
      cssrsRiskStored: isCssrs ? parseCssrsRisk(d['cssrsRisk']) : null,
    );
  }
}

/// An unacknowledged `crisis_events` doc, normalised.
class CrisisRecord {
  final String id;
  final String eventType;
  final String severity;
  final String? title;
  final DateTime? at;

  const CrisisRecord({required this.id, required this.eventType, this.severity = '', this.title, this.at});
}

/// A non-diagnostic signal (check-in indicator, text classifier, anomaly,
/// wearable vitals). Shown separately; never changes [ClinicalStatus.level].
class EarlyWarning {
  final String source;
  final String detail;
  final DateTime? at;

  /// True when the signal crossed its review threshold.
  final bool flagged;

  const EarlyWarning({required this.source, required this.detail, this.at, this.flagged = false});

  String describe(DateTime now) =>
      '$source: $detail${at == null ? '' : ' — ${ClinicalScoring.describeAge(at!, now)}'}';
}

/// Builds the standard early-warning entries from the patient's users doc
/// snapshot. Missing values produce no entry (never a fabricated number).
List<EarlyWarning> earlyWarningsFromSnapshot({
  double? checkInIndicator,
  DateTime? checkInAt,
  double? heartRate,
  DateTime? heartRateAt,
  double heartRateHigh = 120,
  double heartRateLow = 45,
  String? anomalyDescription,
}) {
  final out = <EarlyWarning>[];
  if (checkInIndicator != null && checkInIndicator.isFinite) {
    final v = checkInIndicator.clamp(0, 100).round();
    final strain = v >= 75
        ? 'very high strain reported'
        : v >= 50
            ? 'high strain reported'
            : v >= 25
                ? 'some strain reported'
                : 'little strain reported';
    out.add(EarlyWarning(
      source: 'Check-in wellbeing indicator',
      detail: '$v/100 ($strain; self-report heuristic)',
      at: checkInAt,
      flagged: v >= 50,
    ));
  }
  if (heartRate != null && heartRate.isFinite) {
    final out0 = heartRate > heartRateHigh || heartRate < heartRateLow;
    out.add(EarlyWarning(
      source: 'Wearable heart rate',
      detail: '${heartRate.round()} bpm${out0 ? ' (outside ${heartRateLow.round()}-${heartRateHigh.round()} bpm threshold)' : ''}',
      at: heartRateAt,
      flagged: out0,
    ));
  }
  if (anomalyDescription != null && anomalyDescription.trim().isNotEmpty) {
    out.add(EarlyWarning(
      source: 'Check-in pattern change (statistical)',
      detail: anomalyDescription.trim(),
      flagged: true,
    ));
  }
  return out;
}

class ClinicalStatus {
  final ClinicalLevel level;

  /// False when no PHQ-9 / GAD-7 / C-SSRS exists (UI shows "No data", not "None").
  final bool hasInstrumentData;
  final String primaryDriver;

  /// Human-readable; most severe first, e.g. "PHQ-9 = 18 (moderately severe), 3 days ago".
  final List<String> reasons;

  /// `phq9`, `gad7`, `cssrs` -> date of the latest result (null = never).
  final Map<String, DateTime?> instrumentDates;
  final List<String> staleInstruments;
  final List<EarlyWarning> earlyWarnings;

  /// Clinical workflow step only. Never a treatment or medication.
  final String recommendedAction;

  /// Oldest -> newest, at most 8 values.
  final List<int> phq9History;
  final List<int> gad7History;

  const ClinicalStatus({
    required this.level,
    required this.hasInstrumentData,
    required this.primaryDriver,
    required this.reasons,
    required this.instrumentDates,
    required this.staleInstruments,
    required this.earlyWarnings,
    required this.recommendedAction,
    required this.phq9History,
    required this.gad7History,
  });
}

class _Contribution {
  final ClinicalLevel level;
  final String text;
  final String driver;
  final DateTime? at;
  final bool detailOnly;

  _Contribution(this.level, this.text, this.driver, this.at, {this.detailOnly = false});
}
