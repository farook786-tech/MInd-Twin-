import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/patient_crisis_reporter.dart';
import 'my_twin_screen.dart';
import 'safety_resources_screen.dart';

class PHQ9AssessmentScreen extends StatefulWidget {
  const PHQ9AssessmentScreen({super.key});

  @override
  State<PHQ9AssessmentScreen> createState() => _PHQ9AssessmentScreenState();
}

class _PHQ9AssessmentScreenState extends State<PHQ9AssessmentScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  static const List<_AssessmentQuestion> _questions = <_AssessmentQuestion>[
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Little interest or pleasure in doing things',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Feeling down, depressed, or hopeless',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Trouble falling or staying asleep, or sleeping too much',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Feeling tired or having little energy',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Poor appetite or overeating',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Feeling bad about yourself, or that you are a failure',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Trouble concentrating on things, like reading or watching TV',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Moving or speaking slowly, or feeling restless',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Depression Check',
      prompt: 'Thoughts that you would be better off dead or hurting yourself',
      tool: 'phq9',
    ),
    _AssessmentQuestion(
      section: 'Anxiety Check',
      prompt: 'Feeling nervous, anxious, or on edge',
      tool: 'gad7',
    ),
    _AssessmentQuestion(
      section: 'Anxiety Check',
      prompt: 'Not being able to stop or control worrying',
      tool: 'gad7',
    ),
    _AssessmentQuestion(
      section: 'Anxiety Check',
      prompt: 'Worrying too much about different things',
      tool: 'gad7',
    ),
    _AssessmentQuestion(
      section: 'Anxiety Check',
      prompt: 'Trouble relaxing',
      tool: 'gad7',
    ),
    _AssessmentQuestion(
      section: 'Anxiety Check',
      prompt: 'Being so restless that it is hard to sit still',
      tool: 'gad7',
    ),
    _AssessmentQuestion(
      section: 'Anxiety Check',
      prompt: 'Becoming easily annoyed or irritable',
      tool: 'gad7',
    ),
    _AssessmentQuestion(
      section: 'Anxiety Check',
      prompt: 'Feeling afraid as if something awful might happen',
      tool: 'gad7',
    ),
  ];

  static const List<_AnswerOption> _answerOptions = <_AnswerOption>[
    _AnswerOption(emoji: '😊', label: 'Not at all', score: 0),
    _AnswerOption(emoji: '🙂', label: 'Several days', score: 1),
    _AnswerOption(emoji: '😔', label: 'More than half the days', score: 2),
    _AnswerOption(emoji: '😞', label: 'Nearly every day', score: 3),
  ];

  late final List<int?> _answers;

  int _currentIndex = 0;
  bool _showEncouragement = false;
  bool _isSubmitting = false;
  bool _isComplete = false;

  int _phq9Score = 0;
  int _gad7Score = 0;

  @override
  void initState() {
    super.initState();
    _answers = List<int?>.filled(_questions.length, null);
  }

  int get _selectedScore => _answers[_currentIndex] ?? -1;

  String _phqSeverity(int score) {
    if (score >= 20) return 'severe';
    if (score >= 15) return 'moderately_severe';
    if (score >= 10) return 'moderate';
    if (score >= 5) return 'mild';
    return 'minimal';
  }

  String _gadSeverity(int score) {
    if (score >= 15) return 'severe';
    if (score >= 10) return 'moderate';
    if (score >= 5) return 'mild';
    return 'minimal';
  }

  String _phqInterpretation(int score) {
    if (score >= 20) return 'Severe depression symptoms';
    if (score >= 15) return 'Moderately severe depression symptoms';
    if (score >= 10) return 'Moderate depression symptoms';
    if (score >= 5) return 'Mild depression symptoms';
    return 'Minimal depression symptoms';
  }

  String _gadInterpretation(int score) {
    if (score >= 15) return 'Severe anxiety symptoms';
    if (score >= 10) return 'Moderate anxiety symptoms';
    if (score >= 5) return 'Mild anxiety symptoms';
    return 'Minimal anxiety symptoms';
  }

  /// Saves the assessment ONCE to Firestore. Firestore persists the write in
  /// its offline queue immediately and syncs it when online, so there is no
  /// second (SQLite) queue - that previously produced duplicate assessments
  /// (and duplicate server-side crisis alerts) after a timeout.
  ///
  /// Cloud Function onAssessmentCreated reads `totalScore` (PHQ-9 total),
  /// `item9` (PHQ-9 question 9, 0-3) and `phq9Answers` and raises the
  /// automatic crisis event (total >= 20 or item9 > 0). The client does NOT
  /// write that crisis event itself, to avoid duplicates.
  Future<void> _submitAssessment() async {
    if (_isSubmitting) return;

    final patientId = _authService.currentUserId;
    if (patientId == null || patientId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to submit. Please sign in again.')),
      );
      return;
    }
    if (_answers.any((a) => a == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer every question before submitting.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final phqAnswers = _answers.take(9).map((v) => v!).toList();
    final gadAnswers = _answers.skip(9).map((v) => v!).toList();
    final phq9Score = phqAnswers.fold<int>(0, (a, b) => a + b);
    final gad7Score = gadAnswers.fold<int>(0, (a, b) => a + b);
    final item9 = phqAnswers[8];

    // Server-owned therapistId (never '' / never a name). Unlinked -> null.
    final therapistId = await _authService.loadTherapistId();

    final ref = _firestore.collection('clinical_assessments').doc();

    // PHQ-9 item 9 > 0 (thoughts of being better off dead / self-harm):
    // alert the therapist BEFORE saving, also when offline (the write is
    // queued). Deterministic id `assessment_<assessmentId>` so the Cloud
    // Function's idempotent write for the same assessment merges with it.
    CrisisReportStatus? item9Status;
    if (item9 > 0) {
      item9Status = await PatientCrisisReporter.report(
        eventType: 'phq9_severe',
        severity: item9 >= 2 ? 'critical' : 'high',
        title: 'PHQ-9 item 9: thoughts of death or self-harm',
        message: 'Patient answered "${_answerOptions[item9].label}" to PHQ-9 item 9 '
            '(thoughts that they would be better off dead or of hurting themselves). '
            'PHQ-9 total: $phq9Score.',
        source: 'phq9_assessment',
        details: {'assessmentId': ref.id, 'item9': item9, 'totalScore': phq9Score},
        docId: 'assessment_${ref.id}',
      );
    }

    var queuedOffline = false;
    String? errorMessage;
    try {
      final write = ref.set({
        'patientId': patientId,
        'therapistId': therapistId,
        'type': 'phq9_gad7',
        'totalScore': phq9Score,
        'item9': item9,
        'phq9Answers': phqAnswers,
        'phq9Severity': _phqSeverity(phq9Score),
        'phq9Score': phq9Score, // legacy name kept for older readers
        'gad7Score': gad7Score,
        'gad7Answers': gadAnswers,
        'gad7Severity': _gadSeverity(gad7Score),
        'answers': {
          'phq9': phqAnswers,
          'gad7': gadAnswers,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
      });
      try {
        await write.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        queuedOffline = true;
        unawaited(write.catchError((Object e) => debugPrint('Queued assessment failed: $e')));
      }

      // Patient snapshot: latest PHQ-9 only. latestRiskScore is owned by the
      // daily check-in and is NOT overwritten here.
      unawaited(_firestore.collection('users').doc(patientId).set({
        'latestPhq9': {
          'total': phq9Score,
          'severity': _phqSeverity(phq9Score),
          'at': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true)).catchError((Object e) => debugPrint('PHQ-9 snapshot update failed: $e')));

      if (!queuedOffline) await _flushLegacyPendingAssessments();

      if (!mounted) return;
      setState(() {
        _phq9Score = phq9Score;
        _gad7Score = gad7Score;
        _isComplete = true;
      });
      if (queuedOffline) {
        errorMessage = 'You are offline. Your answers are saved on this device and will sync automatically.';
      }
    } catch (error) {
      debugPrint('Assessment save failed: $error');
      errorMessage = 'Your assessment could not be saved ($error). Please try again.';
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }

    if (!mounted) return;
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), duration: const Duration(seconds: 6)),
      );
    }
    if (item9Status != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(PatientCrisisReporter.describe(item9Status)),
        duration: const Duration(seconds: 8),
        backgroundColor:
            item9Status == CrisisReportStatus.delivered ? AppTheme.safeGreen : AppTheme.riskRed,
      ));
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SafetyResourcesScreen()),
      );
    } else if (_isComplete && phq9Score >= 20) {
      await _showSafetyFollowUp(linked: therapistId != null, offline: queuedOffline);
    }
  }

  Future<void> _showSafetyFollowUp({required bool linked, required bool offline}) async {
    final notifyText = !linked
        ? 'You are not linked to a therapist, so no clinician was notified.'
        : offline
            ? 'Your therapist will be notified as soon as your device reconnects.'
            : 'Your therapist is being notified.';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Your safety matters'),
        content: Text(
          'Some of your answers suggest you may be going through something very hard. '
          '$notifyText\n\nIf you are thinking about hurting yourself, please reach out now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.riskRed),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SafetyResourcesScreen()),
              );
            },
            child: const Text('Get help now'),
          ),
        ],
      ),
    );
  }

  /// Uploads assessments queued in SQLite by OLDER app versions, using the
  /// queue id as the document id so retries can never create duplicates.
  /// New submissions are never queued here.
  Future<void> _flushLegacyPendingAssessments() async {
    try {
      final dbService = DatabaseService();
      final pending = await dbService.getPendingAssessments();
      for (final item in pending) {
        final id = item['id'] as String;
        dynamic answers = item['answers'];
        if (answers is String) {
          try {
            answers = jsonDecode(answers);
          } catch (_) {}
        }
        final phq = (answers is Map && answers['phq9'] is List)
            ? List<int>.from((answers['phq9'] as List).map((e) => (e as num).toInt()))
            : const <int>[];
        final tid = item['therapistId'];
        await _firestore.collection('clinical_assessments').doc(id).set({
          'patientId': item['patientId'],
          'therapistId': (tid is String && tid.isNotEmpty) ? tid : null,
          'type': 'phq9_gad7',
          'totalScore': item['phq9Score'],
          if (phq.length == 9) 'item9': phq[8],
          if (phq.length == 9) 'phq9Answers': phq,
          'phq9Score': item['phq9Score'],
          'gad7Score': item['gad7Score'],
          'answers': answers,
          'timestamp': FieldValue.serverTimestamp(),
          'legacyQueued': true,
        }).timeout(const Duration(seconds: 15));
        await dbService.deletePendingAssessment(id);
      }
    } catch (e) {
      debugPrint('Legacy assessment flush deferred: $e');
    }
  }

  Future<void> _selectAnswer(int score) async {
    if (_isSubmitting || _showEncouragement || _isComplete) {
      return;
    }

    setState(() {
      _answers[_currentIndex] = score;
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _questions.length) {
      await _submitAssessment();
      return;
    }

    if (nextIndex % 3 == 0) {
      setState(() {
        _showEncouragement = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() {
        _showEncouragement = false;
        _currentIndex = nextIndex;
      });
      return;
    }

    setState(() {
      _currentIndex = nextIndex;
    });
  }

  Widget _buildProgress() {
    final progress = (_currentIndex + 1) / _questions.length;
    final question = _questions[_currentIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Question ${_currentIndex + 1} of ${_questions.length}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: progress,
            color: AppTheme.primaryIndigo.withValues(alpha: 0.9),
            backgroundColor: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.cardDark.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(
            question.section,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionBody() {
    final question = _questions[_currentIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          question.prompt,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Take your time with this one 💙',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerButton(_AnswerOption option) {
    final selected = _selectedScore == option.score;
    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      scale: selected ? 1.0 : 0.985,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _selectAnswer(option.score),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: selected
                    ? AppTheme.primaryIndigo.withValues(alpha: 0.25)
                    : AppTheme.cardDark.withValues(alpha: 0.82),
                border: Border.all(
                  color: selected
                      ? AppTheme.primaryIndigo.withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.08),
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryIndigo.withValues(alpha: 0.22),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                children: [
                  Text(option.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.76),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEncouragementCard() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryIndigo.withValues(alpha: 0.24),
              Colors.white.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: const Text(
          'You\'re doing great 💙 Keep going',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildFinalScreen() {
    final phqText = _phqInterpretation(_phq9Score);
    final gadText = _gadInterpretation(_gad7Score);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          radius: 22,
          color: AppTheme.cardDark.withValues(alpha: 0.86),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Assessment complete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              _buildScoreLine('PHQ-9 score', '$_phq9Score / 27', phqText),
              const SizedBox(height: 12),
              _buildScoreLine('GAD-7 score', '$_gad7Score / 21', gadText),
              const SizedBox(height: 18),
              Text(
                'Thank you for being honest today. Your responses help Ally and your care team support you with more precision. 💙',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.4,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyTwinScreen()),
              );
            },
            child: const Text('View My Twin'),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreLine(String title, String score, String interpretation) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            score,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            interpretation,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
        title: const Text(
          'Clinical Check-in',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isComplete
          ? _buildFinalScreen()
          : _isSubmitting
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppTheme.primaryIndigo),
                      SizedBox(height: 14),
                      Text(
                        'Submitting assessment...',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: _showEncouragement
                    ? _buildEncouragementCard()
                    : Column(
                        key: ValueKey<int>(_currentIndex),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProgress(),
                          _buildQuestionBody(),
                          const Spacer(),
                          ..._answerOptions.map(_buildAnswerButton),
                        ],
                      ),
              ),
            ),
    );
  }
}

class _AssessmentQuestion {
  final String section;
  final String prompt;
  final String tool;

  const _AssessmentQuestion({
    required this.section,
    required this.prompt,
    required this.tool,
  });
}

class _AnswerOption {
  final String emoji;
  final String label;
  final int score;

  const _AnswerOption({
    required this.emoji,
    required this.label,
    required this.score,
  });
}
