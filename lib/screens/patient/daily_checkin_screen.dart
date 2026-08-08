import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../services/auth_service.dart';
import '../../services/ml_anomaly_service.dart';
import '../../services/ml_risk_service.dart';
import '../../services/ml_sentiment_service.dart';
import 'breathing_exercise_screen.dart';
import 'my_twin_screen.dart';
import 'safety_resources_screen.dart';
import 'thought_dump_screen.dart';

class DailyCheckInScreen extends StatefulWidget {
  /// When true the screen is rendered inside the patient home tab stack and
  /// must not pop itself out of the navigator.
  final bool embedded;
  final void Function(int index)? onNavigateTab;

  const DailyCheckInScreen({super.key, this.embedded = false, this.onNavigateTab});

  @override
  State<DailyCheckInScreen> createState() => _DailyCheckInScreenState();
}

class _DailyCheckInScreenState extends State<DailyCheckInScreen>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final MlSentimentService _mlSentimentService = MlSentimentService();
  final MlRiskService _mlRiskService = MlRiskService();
  final MlAnomalyService _mlAnomalyService = MlAnomalyService();

  final TextEditingController _optionalGoodThingController = TextEditingController();
  final Random _random = Random();

  late final AnimationController _greetingController;
  late final AnimationController _allyBounceController;

  int _stage = 0;
  bool _isSaving = false;

  String _patientName = 'Friend';
  String _therapistId = '';

  _ChoiceOption? _selectedMood;
  _ChoiceOption? _selectedSleep;
  _ChoiceOption? _selectedEnergy;
  final Set<String> _selectedWorries = <String>{};
  final Set<String> _selectedPositives = <String>{};

  bool _breathingExerciseDone = false;
  String? _breathingFeedback;
  String? _thoughtDump;
  String? _thoughtDumpSentiment;

  String _allyDynamicMessage = 'I am here with you. 💙';

  double _latestRiskScore = 50.0;
  int _streakDays = 0;

  static const List<_ChoiceOption> _moodOptions = <_ChoiceOption>[
    _ChoiceOption(id: 'great', emoji: '😊', title: 'Great', score: 1),
    _ChoiceOption(id: 'okay', emoji: '😐', title: 'Okay', score: 2),
    _ChoiceOption(id: 'sad', emoji: '😔', title: 'Sad', score: 3),
    _ChoiceOption(id: 'anxious', emoji: '😰', title: 'Anxious', score: 4),
    _ChoiceOption(id: 'frustrated', emoji: '😡', title: 'Frustrated', score: 5),
  ];

  static const List<_ChoiceOption> _sleepOptions = <_ChoiceOption>[
    _ChoiceOption(id: 'great', emoji: '😴', title: 'Great (7-9 hours)', score: 1),
    _ChoiceOption(id: 'okay', emoji: '🙂', title: 'Okay (5-7 hours)', score: 2),
    _ChoiceOption(id: 'poor', emoji: '😞', title: 'Poor (3-5 hours)', score: 3),
    _ChoiceOption(id: 'barely_slept', emoji: '❌', title: 'Barely slept (<3 hours)', score: 4),
  ];

  static const List<_ChoiceOption> _energyOptions = <_ChoiceOption>[
    _ChoiceOption(id: 'high', emoji: '⚡', title: 'High energy', score: 1),
    _ChoiceOption(id: 'normal', emoji: '🔋', title: 'Normal energy', score: 2),
    _ChoiceOption(id: 'low', emoji: '🪫', title: 'Low energy', score: 3),
    _ChoiceOption(id: 'drained', emoji: '💀', title: 'Completely drained', score: 4),
  ];

  static const List<_ChoiceOption> _worryOptions = <_ChoiceOption>[
    _ChoiceOption(id: 'work_stress', emoji: '💼', title: 'Work/Study stress'),
    _ChoiceOption(id: 'family_issues', emoji: '👨‍👩‍👧', title: 'Family issues'),
    _ChoiceOption(id: 'financial_worries', emoji: '💰', title: 'Financial worries'),
    _ChoiceOption(id: 'relationship_problems', emoji: '❤️', title: 'Relationship problems'),
    _ChoiceOption(id: 'overwhelmed', emoji: '🌀', title: 'Just feeling overwhelmed'),
    _ChoiceOption(id: 'nothing_specific', emoji: '😶', title: 'Not sure/Nothing specific'),
  ];

  static const List<_ChoiceOption> _positiveOptions = <_ChoiceOption>[
    _ChoiceOption(id: 'good_moment', emoji: '☀️', title: 'Had a good moment'),
    _ChoiceOption(id: 'enjoyed_something', emoji: '🎵', title: 'Enjoyed something'),
    _ChoiceOption(id: 'connected_with_someone', emoji: '👥', title: 'Connected with someone'),
    _ChoiceOption(id: 'outside_time', emoji: '🌿', title: 'Spent time outside'),
    _ChoiceOption(id: 'completed_something', emoji: '✅', title: 'Completed something'),
    _ChoiceOption(id: 'positive_thought', emoji: '💭', title: 'Had a positive thought'),
  ];

  @override
  void initState() {
    super.initState();
    _greetingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _allyBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      lowerBound: 0,
      upperBound: 1,
    );

    final user = _authService.getCurrentUser();
    final name = (user?['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      _patientName = name;
    }

    _loadTherapistId();
  }

  @override
  void dispose() {
    _greetingController.dispose();
    _allyBounceController.dispose();
    _optionalGoodThingController.dispose();
    super.dispose();
  }

  Future<void> _loadTherapistId() async {
    final userId = _authService.currentUserId;
    if (userId == null) {
      return;
    }

    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data() ?? <String, dynamic>{};
      final therapistId = (data['therapistId'] ?? data['assignedTherapist'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        _therapistId = therapistId;
      });
    } catch (e) {
      debugPrint('Failed to load therapist id: $e');
    }
  }

  bool _canProceedCurrentStage() {
    if (_stage == 1) return _selectedMood != null;
    if (_stage == 2) return _selectedSleep != null;
    if (_stage == 3) return _selectedEnergy != null;
    if (_stage == 4) return _selectedWorries.isNotEmpty;
    if (_stage == 5) return _selectedPositives.isNotEmpty;
    return true;
  }

  Future<bool> _handleBackTap() async {
    if (_isSaving) return false;
    if (_stage > 0) {
      setState(() {
        _stage -= 1;
      });
      return false;
    }
    return true;
  }

  String _timeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _pickRandom(List<String> options) {
    if (options.isEmpty) return 'I am here with you. 💙';
    return options[_random.nextInt(options.length)];
  }

  String _comboMoodSleepMessage() {
    final mood = _selectedMood?.id;
    final sleep = _selectedSleep?.id;

    if (mood == null && sleep == null) {
      return 'How are you feeling right now? 💙';
    }

    if (mood == null || sleep == null) {
      if (mood == 'great') {
        return _pickRandom(const <String>[
          'You are bringing great energy today 🌟',
          'Love that you are feeling good today 💙',
          'That positive spark matters ✨',
        ]);
      }
      if (mood == 'sad') {
        return _pickRandom(const <String>[
          'Thank you for saying that out loud 💙',
          'I hear you. You are not alone 🤍',
          'Naming sadness is a brave step 💙',
        ]);
      }
      if (mood == 'anxious') {
        return _pickRandom(const <String>[
          'I am with you. We can take this slowly 💙',
          'Anxiety is heavy. You are doing your best 🌿',
          'One breath at a time is enough today 🌬️',
        ]);
      }
      return 'Thanks for sharing. 💙';
    }

    final key = '$mood|$sleep';
    const matrix = <String, List<String>>{
      'great|great': <String>[
        "You're glowing today! 🌟",
        'What a wonderful combination! 💙',
        'Your body and mind are in sync today ✨',
      ],
      'great|poor': <String>[
        "Even tired, you're showing up 💪",
        'Your spirit is strong despite the fatigue 💙',
        'Rest tonight - you deserve it 🌙',
      ],
      'great|barely_slept': <String>[
        "Even tired, you're showing up 💪",
        'Your spirit is strong despite the fatigue 💙',
        'Rest tonight - you deserve it 🌙',
      ],
      'sad|great': <String>[
        'Sometimes sadness visits even on good days',
        'Sleep was kind to you - let that be enough 💙',
        'Your body rested well. Your heart will too 🌿',
      ],
      'sad|poor': <String>[
        'That sounds really hard. I hear you 💙',
        'Two tough things at once - you are still here 🤍',
        'Thank you for telling me. That took courage 💙',
      ],
      'sad|barely_slept': <String>[
        'That sounds really hard. I hear you 💙',
        'Two tough things at once - you are still here 🤍',
        'Thank you for telling me. That took courage 💙',
      ],
      'anxious|poor': <String>[
        'Anxiety and tiredness together is so heavy 💙',
        'Your nervous system needs care today 🌿',
        'Let us take this one breath at a time 🌬️',
      ],
      'anxious|barely_slept': <String>[
        'Anxiety and tiredness together is so heavy 💙',
        'Your nervous system needs care today 🌿',
        'Let us take this one breath at a time 🌬️',
      ],
      'anxious|great': <String>[
        'Even rested minds can feel anxious 💙',
        'Your body is ready - let us calm the mind 🌿',
        'Anxiety visits even on good sleep nights 💙',
      ],
    };

    final picked = _pickRandom(
      matrix[key] ??
          const <String>[
            'Thank you for checking in with honesty 💙',
            'You are doing something important for yourself today 🌿',
            'I am right here with you 💙',
          ],
    );

    final energy = _selectedEnergy?.id;
    if (energy == 'drained') {
      return '$picked Rest is productive too 🌙';
    }
    if (energy == 'high') {
      return '$picked Use that energy wisely! ⚡';
    }
    return picked;
  }

  String _worriesMessage() {
    if (_selectedWorries.length >= 2) {
      return "That's a lot to carry. You don't have to hold it all alone 💙";
    }
    if (_selectedWorries.contains('work_stress') && _selectedWorries.length == 1) {
      return 'Work pressure is real. You are handling it 💪';
    }
    if (_selectedWorries.contains('family_issues')) {
      return 'Family things can weigh heavy. I see you 💙';
    }
    if (_selectedWorries.contains('nothing_specific')) {
      return 'Sometimes we just feel off. That is okay 🌿';
    }
    return _comboMoodSleepMessage();
  }

  void _refreshAllyMessage() {
    String message;
    if (_stage == 4 && _selectedWorries.isNotEmpty) {
      message = _worriesMessage();
    } else {
      message = _comboMoodSleepMessage();
    }

    setState(() {
      _allyDynamicMessage = message;
    });
    _allyBounceController.forward(from: 0);
  }

  double _riskScoreFromInputs() {
    final moodScore = (_selectedMood?.score ?? 1).toDouble();
    final sleepScore = (_selectedSleep?.score ?? 1).toDouble();
    final energyScore = (_selectedEnergy?.score ?? 1).toDouble();

    final riskScore = (((moodScore - 1) / 4) * 40) +
        (((sleepScore - 1) / 3) * 30) +
        (((energyScore - 1) / 3) * 30);

    return riskScore.clamp(0.0, 100.0);
  }

  double _wellbeingScore() => (100 - _riskScoreFromInputs()).clamp(0.0, 100.0);

  String _riskLevelFromScore(double score) {
    if (score <= 24) return 'low';
    if (score <= 49) return 'moderate';
    if (score <= 74) return 'high';
    return 'critical';
  }

  bool _needsCrisisCheck() {
    final isSadMood = _selectedMood?.id == 'sad';
    final isDrained = _selectedEnergy?.id == 'drained';
    final manyWorries = _selectedWorries.length >= 2;
    return isSadMood && isDrained && manyWorries;
  }

  Future<void> _saveCrisisEventAndOpenResources() async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    try {
      await _firestore.collection('crisis_events').add({
        'patientId': userId,
        'therapistId': _therapistId,
        'eventType': 'self_reported_help_needed',
        'mood': _selectedMood?.id,
        'energy': _selectedEnergy?.id,
        'worries': _selectedWorries.toList(),
        'source': 'daily_checkin',
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to create crisis alert from check-in: $e');
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SafetyResourcesScreen()),
    );
  }

  Future<void> _runCrisisCheckIfNeeded() async {
    if (!_needsCrisisCheck()) return;

    final response = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.cardDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('I want to make sure you are safe'),
          content: const Text('Are you having any thoughts of hurting yourself?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("I'm okay"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.riskRed),
              child: const Text('I need help'),
            ),
          ],
        );
      },
    );

    if (response == true) {
      await _saveCrisisEventAndOpenResources();
    }
  }

  Future<void> _handleActivityAction(_SuggestedActivity activity) async {
    if (activity.id == 'breathing') {
      final feedback = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const BreathingExerciseScreen()),
      );
      if (!mounted || feedback == null) return;
      setState(() {
        _breathingExerciseDone = true;
        _breathingFeedback = feedback;
      });
      return;
    }

    if (activity.id == 'thought_dump') {
      final result = await Navigator.of(context).push<ThoughtDumpResult>(
        MaterialPageRoute(builder: (_) => const ThoughtDumpScreen()),
      );
      if (!mounted || result == null) return;
      setState(() {
        _thoughtDump = result.text;
        _thoughtDumpSentiment = result.sentiment;
      });
      return;
    }

    if (activity.id == 'walk') {
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.cardDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Walk Reminder'),
          content: const Text('Set a reminder to go for a walk?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(30),
              child: const Text('In 30 mins'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(60),
              child: const Text('In 1 hour'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(0),
              child: const Text('Skip'),
            ),
          ],
        ),
      );

      if (selected == null || selected == 0) return;
      final uid = _authService.currentUserId;
      if (uid == null) return;

      try {
        await _firestore.collection('reminders').add({
          'patientId': uid,
          'type': 'walk',
          'scheduledAt': Timestamp.fromDate(DateTime.now().add(Duration(minutes: selected))),
          'completed': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder set! 💙')),
        );
      } catch (e) {
        debugPrint('Failed to set reminder: $e');
      }
    }
  }

  _TinyGoal _goalForToday() {
    if (_selectedEnergy?.id == 'drained' || _selectedSleep?.id == 'barely_slept') {
      return const _TinyGoal(id: 'drink_water', text: 'Drink 2 glasses of water 💧');
    }
    if (_selectedMood?.id == 'anxious') {
      return const _TinyGoal(id: 'deep_breaths', text: 'Take 3 deep breaths 🌬️');
    }
    if (_selectedMood?.id == 'sad') {
      return const _TinyGoal(id: 'text_someone', text: 'Text one person you care about 💌');
    }
    return const _TinyGoal(id: 'small_task', text: "Do one thing you've been putting off ✅");
  }

  String _summaryMessage() {
    final moodPart = switch (_selectedMood?.id) {
      'great' => 'today felt steady and positive',
      'okay' => 'today felt manageable',
      'sad' => 'today felt heavy',
      'anxious' => 'your mind felt on edge',
      'frustrated' => 'frustration showed up strongly',
      _ => 'you checked in with honesty',
    };

    final sleepPart = switch (_selectedSleep?.id) {
      'great' => 'You gave your body restorative sleep.',
      'okay' => 'Your sleep was okay, with room to recharge.',
      'poor' => 'Sleep was limited, which can amplify emotions.',
      'barely_slept' => 'Very little sleep can make everything feel louder.',
      _ => 'Sleep data helps us understand your rhythm.',
    };

    final energyPart = switch (_selectedEnergy?.id) {
      'high' => 'Your energy had momentum.',
      'normal' => 'Your energy stayed fairly balanced.',
      'low' => 'Energy felt lower than your usual baseline.',
      'drained' => 'You are carrying a lot right now.',
      _ => 'Energy patterns are part of your daily rhythm.',
    };

    final highlightedPositive = _selectedPositives.isEmpty
        ? 'a small moment of self-awareness'
        : _positiveOptions
            .firstWhere(
              (option) => _selectedPositives.contains(option.id),
              orElse: () => _positiveOptions.first,
            )
            .title
            .toLowerCase();

    return 'Hey $_patientName... $moodPart. '
        '$sleepPart $energyPart '
        'But you noticed $highlightedPositive - that matters more than you think 💙';
  }

  List<_SuggestedActivity> _activitiesForMood() {
    if (_selectedMood?.id == 'anxious' || _selectedMood?.id == 'sad') {
      return const <_SuggestedActivity>[
        _SuggestedActivity(
          id: 'breathing',
          emoji: '🧘',
          title: '2-min Breathing Reset',
          subtitle: 'Calm your nervous system',
          primaryAction: 'Start Now',
        ),
        _SuggestedActivity(
          id: 'thought_dump',
          emoji: '📝',
          title: 'Thought Dump',
          subtitle: 'Get it out of your head',
          primaryAction: 'Start Now',
        ),
        _SuggestedActivity(
          id: 'walk',
          emoji: '🚶',
          title: '5-min Walk Challenge',
          subtitle: 'Move your body, shift your mood',
          primaryAction: "I'll do this",
        ),
      ];
    }

    return const <_SuggestedActivity>[
      _SuggestedActivity(
        id: 'breathing',
        emoji: '🫧',
        title: '1-min Slow Breath',
        subtitle: 'Reset your pace gently',
        primaryAction: 'Start Now',
      ),
      _SuggestedActivity(
        id: 'thought_dump',
        emoji: '🗒️',
        title: 'Mini Plan',
        subtitle: 'Pick one small next action',
        primaryAction: 'Start Now',
      ),
      _SuggestedActivity(
        id: 'walk',
        emoji: '🎧',
        title: 'Grounding Audio',
        subtitle: 'Give your mind a calm anchor',
        primaryAction: "I'll do this",
      ),
    ];
  }

  Future<int> _calculateAndPersistStreak(String patientId) async {
    final now = DateTime.now();
    final startWindow = now.subtract(const Duration(days: 400));

    final snapshot = await _firestore
        .collection('daily_logs')
        .where('patientId', isEqualTo: patientId)
        .limit(400)
        .get();

    final loggedDates = <DateTime>{};
    for (final doc in snapshot.docs) {
      final ts = doc.data()['timestamp'];
      if (ts is! Timestamp) continue;
      final d = ts.toDate();
      if (d.isBefore(startWindow)) continue;
      loggedDates.add(DateTime(d.year, d.month, d.day));
    }

    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    while (loggedDates.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    await _firestore.collection('users').doc(patientId).set({
      'streak': streak,
      'lastStreakUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return streak;
  }

  Future<void> _saveDailyCheckIn() async {
    if (_isSaving) return;

    final patientId = _authService.currentUserId;
    if (patientId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save check-in. Please sign in again.')),
      );
      return;
    }

    final mood = _selectedMood;
    final sleep = _selectedSleep;
    final energy = _selectedEnergy;
    if (mood == null || sleep == null || energy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all steps before saving.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final wellbeingScore = _wellbeingScore();
    final estimatedRiskScore = _riskScoreFromInputs();
    final todayGoal = _goalForToday();

    final moodTextForNlp = <String>[
      mood.title,
      sleep.title,
      energy.title,
      ..._selectedWorries,
      ..._selectedPositives,
      _optionalGoodThingController.text.trim(),
      _thoughtDump ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');

    DocumentReference<Map<String, dynamic>> dailyLogRef;
    final finalRiskScore = estimatedRiskScore;

    try {
      dailyLogRef = await _firestore.collection('daily_logs').add({
        'patientId': patientId,
        'therapistId': _therapistId,
        'mood': mood.title,
        'moodKey': mood.id,
        'moodScore': mood.score,
        'sleep': sleep.title,
        'sleepKey': sleep.id,
        'sleepScore': sleep.score,
        'energy': energy.title,
        'energyKey': energy.id,
        'energyScore': energy.score,
        'worries': _selectedWorries.toList(),
        'positives': _selectedPositives.toList(),
        'dailyGoal': todayGoal.text,
        'dailyGoalKey': todayGoal.id,
        'goalLabel': todayGoal.text,
        'goalCompleted': false,
        'timestamp': FieldValue.serverTimestamp(),
        'wellbeingScore': wellbeingScore,
        'riskScore': estimatedRiskScore,
        'summaryText': _summaryMessage(),
        'optionalNote': _optionalGoodThingController.text.trim(),
        'breathingExerciseDone': _breathingExerciseDone,
        if (_breathingFeedback != null) 'breathingFeedback': _breathingFeedback,
        if (_thoughtDump != null) 'thoughtDump': _thoughtDump,
        if (_thoughtDumpSentiment != null) 'thoughtDumpSentiment': _thoughtDumpSentiment,
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save check-in: $error')),
      );
      return;
    }

    SentimentResult? sentimentResult;
    RiskPrediction? riskPrediction;
    AnomalyResult? anomalyResult;

    try {
      sentimentResult = await _mlSentimentService.analyzeSentiment(moodTextForNlp);
    } catch (e) {
      debugPrint('Sentiment analysis failed: $e');
    }

    try {
      riskPrediction = await _mlRiskService.predictRisk(patientId);
    } catch (e) {
      debugPrint('Risk prediction failed: $e');
    }

    try {
      anomalyResult = await _mlAnomalyService.detectAnomaly(patientId);
    } catch (e) {
      debugPrint('Anomaly detection failed: $e');
    }

    try {
      await dailyLogRef.set({
        if (sentimentResult != null)
          'mlSentiment': {
            'sentiment': sentimentResult.sentiment,
            'emotion': sentimentResult.emotion,
            'score': sentimentResult.score,
            'confidence': sentimentResult.confidence,
            'clinicalFlags': sentimentResult.clinicalFlags,
            'crisisKeywords': sentimentResult.crisisKeywords,
          },
        if (riskPrediction != null)
          'mlRisk': {
            'riskScore': riskPrediction.riskScore,
            'riskLevel': riskPrediction.riskLevel,
            'trend': riskPrediction.trend,
            'prediction7Days': riskPrediction.prediction7Days,
            'keyFactors': riskPrediction.keyFactors,
            'confidence': riskPrediction.confidence,
            'source': riskPrediction.source,
          },
        if (anomalyResult != null)
          'mlAnomaly': {
            'anomalyDetected': anomalyResult.anomalyDetected,
            'anomalyType': anomalyResult.anomalyType,
            'severity': anomalyResult.severity,
            'description': anomalyResult.description,
            'recommendation': anomalyResult.recommendation,
            'confidence': anomalyResult.confidence,
          },
        'riskScore': finalRiskScore,
        'wellbeingScore': (100 - finalRiskScore).clamp(0.0, 100.0),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save daily log with ML data: $e');
    }

    int streak = 0;
    try {
      streak = await _calculateAndPersistStreak(patientId);
    } catch (e) {
      debugPrint('Failed to calculate streak: $e');
    }

    try {
      await _firestore.collection('users').doc(patientId).set({
        'latestMood': mood.title,
        'latestRiskScore': finalRiskScore,
        'latestRiskLevel': _riskLevelFromScore(finalRiskScore),
        'latestWellbeingScore': (100 - finalRiskScore).clamp(0.0, 100.0),
        'lastCheckInDate': FieldValue.serverTimestamp(),
        'lastCheckInAt': FieldValue.serverTimestamp(),
        'streak': streak,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to update user summary: $e');
    }

    if (!mounted) return;
    setState(() {
      _latestRiskScore = finalRiskScore;
      _streakDays = streak;
      _isSaving = false;
      _stage = 9;
    });
  }

  Future<void> _onPrimaryAction() async {
    if (_isSaving) return;

    if (!_canProceedCurrentStage()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an option to continue.')),
      );
      return;
    }

    if (_stage == 5) {
      await _runCrisisCheckIfNeeded();
      if (!mounted) return;
      setState(() {
        _stage = 6;
      });
      return;
    }

    if (_stage == 8) {
      await _saveDailyCheckIn();
      return;
    }

    if (_stage < 9) {
      setState(() {
        _stage += 1;
      });
    }
  }

  Widget _buildProgressBar() {
    if (_stage < 1 || _stage > 5) return const SizedBox.shrink();

    final current = _stage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $current of 5',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 280),
          tween: Tween<double>(begin: 0, end: current / 5),
          builder: (context, value, child) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: value,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                color: AppTheme.primaryIndigo.withValues(alpha: 0.85),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAvatar({double size = 120, bool smiling = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryIndigo.withValues(alpha: 0.55),
            AppTheme.accentCyan.withValues(alpha: 0.22),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryIndigo.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(
        smiling ? Icons.sentiment_very_satisfied_rounded : Icons.sentiment_satisfied_alt_rounded,
        color: Colors.white,
        size: size * 0.45,
      ),
    );
  }

  Widget _buildAllyReply(String text) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 1, end: 1.1).animate(
              CurvedAnimation(parent: _allyBounceController, curve: Curves.easeOutBack),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryIndigo.withValues(alpha: 0.8),
                    AppTheme.accentCyan.withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: const Icon(Icons.favorite, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceTile({
    required _ChoiceOption option,
    required bool selected,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: selected ? 1 : 0.98,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          splashColor: AppTheme.primaryIndigo.withValues(alpha: 0.12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: compact ? 12 : 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? AppTheme.primaryIndigo.withValues(alpha: 0.24)
                  : AppTheme.cardDark.withValues(alpha: 0.72),
              border: Border.all(
                color: selected
                    ? AppTheme.primaryIndigo.withValues(alpha: 0.88)
                    : Colors.white.withValues(alpha: 0.08),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Text(option.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.title,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.72),
                      fontSize: compact ? 16 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceGrid({
    required List<_ChoiceOption> options,
    required bool Function(_ChoiceOption option) isSelected,
    required void Function(_ChoiceOption option) onTap,
  }) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: options.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
      ),
      itemBuilder: (context, index) {
        final option = options[index];
        return _buildChoiceTile(
          option: option,
          selected: isSelected(option),
          onTap: () => onTap(option),
          compact: true,
        );
      },
    );
  }

  Widget _buildPrimaryButton({required String label}) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _onPrimaryAction,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          backgroundColor: AppTheme.primaryIndigo,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildGreetingStage() {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _greetingController, curve: Curves.easeOut),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _buildAvatar(size: 180),
          const SizedBox(height: 24),
          Text(
            '${_timeBasedGreeting()}, $_patientName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'How are you feeling today?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap to tell me',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 36),
          _buildPrimaryButton(label: 'Start check-in'),
        ],
      ),
    );
  }

  Widget _buildMoodStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How are you feeling?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 16),
        _buildChoiceGrid(
          options: _moodOptions,
          isSelected: (option) => _selectedMood?.id == option.id,
          onTap: (option) {
            setState(() {
              _selectedMood = _selectedMood?.id == option.id ? null : option;
            });
            _refreshAllyMessage();
          },
        ),
        const SizedBox(height: 16),
        _buildAllyReply(_allyDynamicMessage),
        const SizedBox(height: 24),
        if (_selectedMood != null) _buildPrimaryButton(label: 'Next →'),
      ],
    );
  }

  Widget _buildSleepStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How was your sleep?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 16),
        ..._sleepOptions.map(
          (option) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildChoiceTile(
              option: option,
              selected: _selectedSleep?.id == option.id,
              onTap: () {
                setState(() {
                  _selectedSleep = _selectedSleep?.id == option.id ? null : option;
                });
                _refreshAllyMessage();
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildAllyReply(_allyDynamicMessage),
        const SizedBox(height: 22),
        if (_selectedSleep != null) _buildPrimaryButton(label: 'Next →'),
      ],
    );
  }

  Widget _buildEnergyStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How is your energy?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 16),
        ..._energyOptions.map(
          (option) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildChoiceTile(
              option: option,
              selected: _selectedEnergy?.id == option.id,
              onTap: () {
                setState(() {
                  _selectedEnergy = _selectedEnergy?.id == option.id ? null : option;
                });
                _refreshAllyMessage();
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildAllyReply(_allyDynamicMessage),
        const SizedBox(height: 22),
        if (_selectedEnergy != null) _buildPrimaryButton(label: 'Next →'),
      ],
    );
  }

  Widget _buildWorriesStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What is weighing on you?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap all that apply',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.64), fontSize: 13),
        ),
        const SizedBox(height: 14),
        ..._worryOptions.map(
          (option) {
            final selected = _selectedWorries.contains(option.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildChoiceTile(
                option: option,
                selected: selected,
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedWorries.remove(option.id);
                    } else {
                      _selectedWorries.add(option.id);
                    }
                  });
                  _refreshAllyMessage();
                },
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildAllyReply(_allyDynamicMessage),
        const SizedBox(height: 22),
        if (_selectedWorries.isNotEmpty) _buildPrimaryButton(label: 'Next →'),
      ],
    );
  }

  Widget _buildPositivesStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'One good thing today',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap what happened',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.64), fontSize: 13),
        ),
        const SizedBox(height: 14),
        ..._positiveOptions.map(
          (option) {
            final selected = _selectedPositives.contains(option.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildChoiceTile(
                option: option,
                selected: selected,
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedPositives.remove(option.id);
                    } else {
                      _selectedPositives.add(option.id);
                    }
                  });
                  _refreshAllyMessage();
                },
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _optionalGoodThingController,
          maxLines: 2,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Want to add more? (optional)',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            filled: true,
            fillColor: AppTheme.cardDark.withValues(alpha: 0.75),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppTheme.primaryIndigo.withValues(alpha: 0.65)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildAllyReply(_allyDynamicMessage),
        const SizedBox(height: 22),
        if (_selectedPositives.isNotEmpty) _buildPrimaryButton(label: 'See summary →'),
      ],
    );
  }

  Widget _buildSummaryStage() {
    return TweenAnimationBuilder<Offset>(
      duration: const Duration(milliseconds: 700),
      tween: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero),
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) {
        return Transform.translate(offset: Offset(0, offset.dy * 80), child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(child: _buildAvatar(size: 120)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.06),
                  AppTheme.primaryIndigo.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Text(
              _summaryMessage(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Risk score ${_riskScoreFromInputs().toStringAsFixed(0)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
          ),
          const SizedBox(height: 26),
          _buildPrimaryButton(label: 'See what helps →'),
        ],
      ),
    );
  }

  Widget _buildActivitiesStage() {
    final activities = _activitiesForMood();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Suggested right now',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 14),
        ...activities.map(
          (activity) => AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            color: AppTheme.cardDark.withValues(alpha: 0.88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${activity.emoji} ${activity.title}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  activity.subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.66), fontSize: 13),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _handleActivityAction(activity),
                      child: Text(activity.primaryAction),
                    ),
                    const SizedBox(width: 10),
                    TextButton(onPressed: () {}, child: const Text('Maybe later')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildPrimaryButton(label: 'Continue →'),
      ],
    );
  }

  Widget _buildGoalStage() {
    final goal = _goalForToday();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryIndigo.withValues(alpha: 0.28),
                AppTheme.accentCyan.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Goal 🎯",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                goal.text,
                style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.35, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _buildPrimaryButton(label: "I'll do it! ✓"),
      ],
    );
  }

  Widget _buildCompletionStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        _buildAvatar(size: 160, smiling: true),
        const SizedBox(height: 20),
        const Text(
          'Check-in complete 💙',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          '🔥 Day $_streakDays streak!',
          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Your twin has been updated',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 15),
        ),
        const SizedBox(height: 24),
        Text(
          'Latest risk ${_latestRiskScore.toStringAsFixed(0)}',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.46), fontSize: 12),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (widget.embedded) {
                widget.onNavigateTab?.call(2);
              } else {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTwinScreen()));
              }
            },
            child: const Text('View My Twin'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              if (widget.embedded) {
                widget.onNavigateTab?.call(0);
              } else {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Back to Home'),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStageBody() {
    if (_stage == 0) return _buildGreetingStage();
    if (_stage == 1) return _buildMoodStage();
    if (_stage == 2) return _buildSleepStage();
    if (_stage == 3) return _buildEnergyStage();
    if (_stage == 4) return _buildWorriesStage();
    if (_stage == 5) return _buildPositivesStage();
    if (_stage == 6) return _buildSummaryStage();
    if (_stage == 7) return _buildActivitiesStage();
    if (_stage == 8) return _buildGoalStage();
    return _buildCompletionStage();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == 0 && !_isSaving,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackTap();
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppTheme.backgroundDark,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: widget.embedded
              ? null
              : IconButton(
                  onPressed: () async {
                    final canPop = await _handleBackTap();
                    if (canPop && mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
          title: const Text('Ally Check-In', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.backgroundDark,
                AppTheme.cardDark.withValues(alpha: 0.72),
              ],
            ),
          ),
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: ListView(
                key: ValueKey<int>(_stage),
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  _buildProgressBar(),
                  if (_stage >= 1 && _stage <= 5) const SizedBox(height: 16),
                  _buildCurrentStageBody(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceOption {
  final String id;
  final String emoji;
  final String title;
  final int score;

  const _ChoiceOption({
    required this.id,
    required this.emoji,
    required this.title,
    this.score = 0,
  });
}

class _SuggestedActivity {
  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final String primaryAction;

  const _SuggestedActivity({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.primaryAction,
  });
}

class _TinyGoal {
  final String id;
  final String text;

  const _TinyGoal({required this.id, required this.text});
}
