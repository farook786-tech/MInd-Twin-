import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/clinical_scoring.dart';
import '../../services/patient_crisis_reporter.dart';
import 'safety_resources_screen.dart';

/// Columbia-Suicide Severity Rating Scale (C-SSRS) Screener, "Screen Version –
/// Recent" — The Columbia Lighthouse Project (https://cssrs.columbia.edu),
/// Posner et al., Am J Psychiatry 2011;168:1266-1277. Free for clinical use.
///
/// The question wording below is the published screener wording and must NOT
/// be paraphrased (that would invalidate the instrument). Gentleness comes from
/// the framing around the questions, one question per page, and the
/// always-visible way out to help.
///
/// Skip logic and triage live in [ClinicalScoring] (unit-tested):
/// Q3-Q5 only if Q2 = yes; the 3-month follow-up only if Q6 = yes.
/// HIGH (Q4, Q5, or Q6 within 3 months): a critical `crisis_events/assessment_<id>`
/// (`cssrs_high`) is written BEFORE the assessment, then the safety screen opens.
/// MODERATE: the Cloud Function raises a `cssrs_moderate` (medium) alert.
class CssrsScreenerScreen extends StatefulWidget {
  /// Where the screener was offered from (diagnostics on the crisis event only):
  /// `phq9_item9`, `patient_home`, `weekly_prompt`.
  final String source;

  const CssrsScreenerScreen({super.key, this.source = 'patient_home'});

  @override
  State<CssrsScreenerScreen> createState() => _CssrsScreenerScreenState();
}

class _CssrsQuestion {
  final String text;
  final String? hint;
  const _CssrsQuestion(this.text, [this.hint]);
}

const Map<String, _CssrsQuestion> _questions = {
  'q1': _CssrsQuestion(
    'In the past month, have you wished you were dead or wished you could go to sleep and not wake up?',
  ),
  'q2': _CssrsQuestion(
    'In the past month, have you actually had any thoughts of killing yourself?',
  ),
  'q3': _CssrsQuestion(
    'In the past month, have you been thinking about how you might do this?',
    'For example: "I thought about taking an overdose but I never made a specific plan as to when, '
        'where or how I would actually do it… and I would never go through with it."',
  ),
  'q4': _CssrsQuestion(
    'In the past month, have you had these thoughts and had some intention of acting on them?',
    'As opposed to "I have the thoughts but I definitely will not do anything about them."',
  ),
  'q5': _CssrsQuestion(
    'In the past month, have you started to work out or worked out the details of how to kill yourself? '
    'Do you intend to carry out this plan?',
  ),
  'q6': _CssrsQuestion(
    'Have you ever done anything, started to do anything, or prepared to do anything to end your life?',
    'Examples: collected pills, obtained a gun, gave away valuables, wrote a will or suicide note, took out '
        'pills but didn\'t swallow any, held a gun but changed your mind or it was grabbed from your hand, '
        'went to the roof but didn\'t jump; or actually took pills, tried to shoot yourself, cut yourself, '
        'tried to hang yourself, etc.',
  ),
  'q6Recent': _CssrsQuestion('Was this within the past 3 months?'),
};

enum _Stage { intro, question, submitting, done }

class _CssrsScreenerScreenState extends State<CssrsScreenerScreen> {
  final AuthService _authService = AuthService();

  /// Answers in the order asked (insertion-ordered map).
  final Map<String, bool> _answered = <String, bool>{};
  _Stage _stage = _Stage.intro;
  CssrsTriage? _triage;
  bool _linked = true;
  bool _queuedOffline = false;
  String? _error;

  String? get _current => ClinicalScoring.nextCssrsQuestion(_answered);

  void _answer(bool yes) {
    final q = _current;
    if (q == null) return;
    setState(() => _answered[q] = yes);
    if (ClinicalScoring.nextCssrsQuestion(_answered) == null) {
      _submit();
    }
  }

  void _back() {
    if (_answered.isEmpty) {
      setState(() => _stage = _Stage.intro);
      return;
    }
    setState(() => _answered.remove(_answered.keys.last));
  }

  Future<void> _submit() async {
    final patientId = _authService.currentUserId;
    if (patientId == null || patientId.isEmpty) {
      setState(() => _error = 'Unable to save. Please sign in again.');
      return;
    }
    final answers = CssrsAnswers.fromAnswered(_answered);
    final triage = ClinicalScoring.triageCssrs(answers);
    setState(() {
      _stage = _Stage.submitting;
      _triage = triage;
      _error = null;
    });

    final firestore = FirebaseFirestore.instance;
    final therapistId = await _authService.loadTherapistId();
    _linked = therapistId != null;
    final ref = firestore.collection('clinical_assessments').doc();

    // HIGH: alert the therapist FIRST (works offline: queued), with the same
    // deterministic id the Cloud Function uses, so it merges instead of duplicating.
    CrisisReportStatus? crisisStatus;
    if (triage.risk == CssrsRisk.high) {
      crisisStatus = await PatientCrisisReporter.report(
        eventType: 'cssrs_high',
        severity: 'critical',
        title: 'C-SSRS screener: HIGH risk (Columbia triage)',
        message: 'Patient answered yes to: '
            '${triage.positiveItems.map(ClinicalScoring.cssrsItemLabel).join('; ')}. '
            'Columbia triage: HIGH — immediate safety assessment.',
        source: 'cssrs_screener',
        details: {
          'assessmentId': ref.id,
          'cssrsRisk': triage.risk.name,
          'positiveItems': triage.positiveItems,
          'offeredFrom': widget.source,
        },
        docId: 'assessment_${ref.id}',
      );
    }

    try {
      final write = ref.set({
        'patientId': patientId,
        'therapistId': therapistId,
        'type': 'cssrs',
        'cssrsAnswers': answers.toFirestore(),
        'cssrsRisk': triage.risk.name,
        'timestamp': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
      });
      try {
        await write.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        _queuedOffline = true;
        unawaited(write.catchError((Object e) => debugPrint('Queued C-SSRS failed: $e')));
      }
      // Snapshot for the therapist roster sort and the weekly prompt.
      unawaited(firestore.collection('users').doc(patientId).set({
        'latestCssrs': {'risk': triage.risk.name, 'at': FieldValue.serverTimestamp()},
      }, SetOptions(merge: true)).catchError((Object e) => debugPrint('C-SSRS snapshot failed: $e')));
    } catch (e) {
      debugPrint('C-SSRS save failed: $e');
      if (!mounted) return;
      setState(() {
        _stage = _Stage.question;
        _answered.remove(_answered.keys.last);
        _error = 'Your answers could not be saved. Please try the last question again.';
      });
      if (crisisStatus == null) return;
    }

    if (!mounted) return;
    if (triage.risk == CssrsRisk.high) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: Text(PatientCrisisReporter.describe(crisisStatus!)),
        duration: const Duration(seconds: 8),
        backgroundColor: crisisStatus == CrisisReportStatus.delivered ? AppTheme.safeGreen : AppTheme.riskRed,
      ));
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SafetyResourcesScreen()),
      );
      return;
    }
    setState(() => _stage = _Stage.done);
  }

  void _openSafety() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SafetyResourcesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
        title: const Text('Safety check-in', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton.icon(
            onPressed: _openSafety,
            icon: Icon(Icons.support_rounded, color: AppTheme.riskRed),
            label: Text('Get help now', style: TextStyle(color: AppTheme.riskRed)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: switch (_stage) {
            _Stage.intro => _buildIntro(),
            _Stage.question => _buildQuestion(),
            _Stage.submitting => const Center(child: CircularProgressIndicator()),
            _Stage.done => _buildDone(),
          },
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'A few questions about how safe you have been feeling',
          style: TextStyle(color: AppColors.ink, fontSize: 24, fontWeight: FontWeight.w700, height: 1.25),
        ),
        const SizedBox(height: 14),
        Text(
          'These are standard questions that clinicians ask everyone. There are no right or wrong answers, '
          'and answering honestly helps your care team support you. It takes about a minute.\n\n'
          'Your answers are shared with your therapist. If you ever feel you might act on thoughts of '
          'ending your life, please use "Get help now" or call your local emergency number.',
          style: TextStyle(color: AppColors.ink.withValues(alpha: 0.8), fontSize: 15, height: 1.45),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _stage = _Stage.question),
            child: const Text('Start'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Not now'),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestion() {
    final id = _current;
    if (id == null) return const Center(child: CircularProgressIndicator());
    final q = _questions[id]!;
    return Column(
      key: ValueKey(id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _back,
              icon: Icon(Icons.arrow_back_rounded, color: AppColors.ink70),
              tooltip: 'Previous question',
            ),
            Text(
              'Question ${_answered.length + 1}',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65), fontSize: 13),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppTheme.riskRed)),
        ],
        const SizedBox(height: 18),
        Text(
          q.text,
          style: TextStyle(color: AppColors.ink, fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
        ),
        if (q.hint != null) ...[
          const SizedBox(height: 12),
          Text(q.hint!, style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65), fontSize: 14, height: 1.4)),
        ],
        const SizedBox(height: 12),
        Text(
          'Take your time. 💙',
          style: TextStyle(color: AppColors.ink.withValues(alpha: 0.55), fontSize: 14),
        ),
        const Spacer(),
        _answerButton('Yes', true),
        const SizedBox(height: 10),
        _answerButton('No', false),
      ],
    );
  }

  Widget _answerButton(String label, bool value) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: AppColors.ink.withValues(alpha: 0.25)),
          backgroundColor: AppTheme.cardDark.withValues(alpha: 0.8),
        ),
        onPressed: () => _answer(value),
        child: Text(label, style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildDone() {
    final risk = _triage?.risk ?? CssrsRisk.none;
    final String message;
    switch (risk) {
      case CssrsRisk.moderate:
        final String notified = _linked
            ? (_queuedOffline
                ? 'Your therapist will see your answers as soon as your device reconnects, and will review them soon.'
                : 'Your therapist has been asked to review your answers soon.')
            : 'You are not linked to a therapist, so no clinician has been notified.';
        message = '$notified\n\nIf you feel unsafe at any point, please use the help options now — you do not have to wait.';
      case CssrsRisk.low:
        message = 'Thank you for sharing this. Thoughts like these are worth talking about, and support is '
            'available any time. Your therapist will see your answers.\n\n'
            'If the thoughts get stronger or you feel unsafe, please reach out straight away.';
      case CssrsRisk.none:
      case CssrsRisk.high:
        message = 'Thank you for answering. Checking in like this regularly helps your care team support you.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Thank you', style: TextStyle(color: AppColors.ink, fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Text(message, style: TextStyle(color: AppColors.ink.withValues(alpha: 0.82), fontSize: 15, height: 1.45)),
        if (_queuedOffline) ...[
          const SizedBox(height: 12),
          Text(
            'You are offline. Your answers are saved on this device and will sync automatically.',
            style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6), fontSize: 13),
          ),
        ],
        const Spacer(),
        if (risk != CssrsRisk.none)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.riskRed),
              onPressed: _openSafety,
              child: const Text('See support options'),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
        ),
      ],
    );
  }
}
