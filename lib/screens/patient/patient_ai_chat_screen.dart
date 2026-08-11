import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/gemini_service.dart';
import '../../services/ml_sentiment_service.dart';
import '../../services/patient_memory_service.dart';
import 'safety_resources_screen.dart';

class PatientAIChatScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const PatientAIChatScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientAIChatScreen> createState() => _PatientAIChatScreenState();
}

class _PatientAIChatScreenState extends State<PatientAIChatScreen> {
  final GeminiService _geminiService = GeminiService();
  final MlSentimentService _mlSentimentService = MlSentimentService();
  final BackendApiService _backendApi = BackendApiService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
      id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      message:
          'Hey there! I\'m Ally, your supportive companion. I\'m here to listen and help you feel supported. How are you doing today?',
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    // Add user message to UI
    setState(() {
      _messages.add(ChatMessage(
        id: DateTime.now().toString(),
        role: 'user',
        message: messageText,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
      _errorMessage = null;
    });

    _messageController.clear();

    try {
      final history = _messages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .map((m) => '${m.role}: ${m.message}')
          .toList();

      final aiText = await _geminiService.generateResponseAdvanced(
        systemPrompt:
            'You are Ally, a warm and supportive friend helping someone with '
            'their mental health journey through the MindTwin app. Speak '
            'naturally like a caring friend would - empathetic, understanding, '
            'and encouraging. Be warm, genuine, non-judgmental, optimistic but '
            'realistic. Use casual, friendly language ("Hey", "I\'m here for '
            'you", "That sounds tough"). Listen and validate feelings, share '
            'coping strategies and wellness tips in a friendly way, encourage '
            'healthy habits and celebrate small wins. Never diagnose or replace '
            'professional help; never be preachy. If crisis signs appear, '
            'immediately suggest the crisis helpline (988) with care. Keep '
            'responses conversational, warm and under 100 words.'
            '${await PatientMemoryService().buildContext(patientId: widget.patientId, currentMessage: messageText)}',
        userPrompt: messageText,
        history: history.take(6).toList(),
        maxWords: 100,
      );

      setState(() {
        _isLoading = false;
        _messages.add(ChatMessage(
          id: DateTime.now().toString(),
          role: 'assistant',
          message: aiText,
          timestamp: DateTime.now(),
        ));
      });

      // Run after the reply is committed so an escalation dialog never pops
      // mid-reply; _runCrisisDetection swallows its own errors.
      await _runCrisisDetection(messageText);
    } catch (e) {
      setState(() {
        _errorMessage = 'Ally is unavailable right now. Please try again in a moment.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runCrisisDetection(String messageText) async {
    final userHistory = _messages
        .where((m) => m.role == 'user')
        .map((m) => m.message)
        .toList();
    // Match the amount of context fed to the Gemini prompt (6 turns).
    final recentHistory = userHistory.length > 6
        ? userHistory.sublist(userHistory.length - 6)
        : userHistory;

    // 1. Primary path: ML bridge (server-side model + phrase + idiom decision).
    try {
      final result = await _backendApi.predictCrisis(
        text: messageText,
        patientId: widget.patientId,
        recentHistory: recentHistory,
      );
      if (result != null && result['available'] == true) {
        final decision = (result['decision'] as Map<String, dynamic>?) ?? {};
        final severity = (decision['severity'] ?? 'low').toString();
        if (decision['escalate'] == true) {
          await _writeCrisisEvent(
            message: messageText,
            severity: severity,
            triggerLayer: (decision['trigger_layer'] ?? 'model').toString(),
            matchedPhrases:
                List<String>.from(decision['matched_phrases'] ?? const []),
            confidence: ((decision['confidence'] ?? 0) as num).toDouble(),
            modelVersion: result['model_version']?.toString() ?? 'unknown',
          );
          await _handleEscalation(severity);
        }
        return;
      }
    } catch (_) {
      // Fall through to local detection if the bridge call failed.
    }

    // 2. Fallback: local phrase-based detection when the ML bridge is unavailable.
    try {
      final local = await _mlSentimentService.detectCrisis(
        messageText,
        widget.patientId,
        recentHistory,
      );
      if (!local.crisisDetected) return;

      await _writeCrisisEvent(
        message: messageText,
        severity: local.severity,
        triggerLayer: 'local:${local.triggerLayer}',
        matchedPhrases: local.matchedPhrases,
        confidence: local.confidence,
        modelVersion: 'local',
      );
      await _handleEscalation(local.severity);
    } catch (_) {
      // Keep chat flow uninterrupted if crisis detection fails.
    }
  }

  Future<void> _writeCrisisEvent({
    required String message,
    required String severity,
    required String triggerLayer,
    required List<String> matchedPhrases,
    required double confidence,
    required String modelVersion,
  }) async {
    String therapistId = '';
    try {
      final userDoc = await _firestore.collection('users').doc(widget.patientId).get();
      therapistId = (userDoc.data()?['therapistId'] ?? '').toString();
    } catch (e) {
      debugPrint('Failed to load therapist id for crisis event: $e');
    }

    await _firestore.collection('crisis_events').add({
      'patientId': widget.patientId,
      'patientName': widget.patientName,
      'therapistId': therapistId,
      'message': message,
      'severity': severity,
      'triggerLayer': triggerLayer,
      'matchedPhrases': matchedPhrases,
      'confidence': confidence,
      'modelVersion': modelVersion,
      'recommendedAction': severity == 'critical' || severity == 'high'
          ? 'Open safety resources and contact support immediately.'
          : 'Offer grounding and encourage therapist follow-up.',
      'safetyPlan': severity == 'critical' || severity == 'high'
          ? 'Move to a safe place, call local emergency services, and contact a trusted person.'
          : 'Pause, breathe slowly, and use coping steps before deciding on next action.',
      'acknowledged': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _handleEscalation(String severity) async {
    if (!mounted) return;

    if (severity == 'critical') {
      final action = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardDark,
          title: const Text('Immediate Support Needed 🆘'),
          content: const Text(
            "I'm really concerned about you right now. You're not alone. "
            'Would you like me to connect you with your therapist immediately?\n\n'
            'National Crisis Helpline: iCall 9152987821',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Open Safety Resources'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Connect Therapist'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (action == true) {
        final sent = await _backendApi.sendSosAlert({
          'patientId': widget.patientId,
          'description': 'Patient requested immediate therapist contact during a critical conversation.',
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sent
                  ? 'Your therapist has been alerted immediately.'
                  : 'Alert queued. Please use the crisis helpline below for immediate support.',
            ),
            backgroundColor: sent ? AppTheme.riskRed : AppTheme.warningAmber,
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SafetyResourcesScreen()),
        );
      }
    } else if (severity == 'high') {
      setState(() {
        _messages.add(ChatMessage(
          id: 'care_${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          message:
              'I hear how heavy this feels right now. I am here with you. '
              'Let us take one small step together and bring in extra support from your therapist.',
          timestamp: DateTime.now(),
        ));
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue[100],
              radius: 16,
              child: Icon(Icons.favorite, color: Colors.blue[700], size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Ally - Your Support Friend'),
          ],
        ),
        elevation: 2,
        actions: const [
          SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: AppTheme.riskRed.withValues(alpha: 0.2),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.riskRed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          
          // Chat messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Start a conversation',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Text(
                            'Meet Ally, your supportive friend here to listen, understand, and help you feel better. Start chatting whenever you need someone to talk to.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];
                      final isUser = message.role == 'user';

                      return Row(
                        mainAxisAlignment: isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!isUser)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: CircleAvatar(
                                backgroundColor: Colors.blue[100],
                                child: Icon(Icons.favorite, color: Colors.blue[700]),
                              ),
                            ),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isUser ? Colors.blue[600] : AppTheme.cardDark,
                                border: isUser ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: isUser
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.message,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('HH:mm').format(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isUser
                                          ? Colors.white70
                                          : Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isUser)
                            const Padding(
                              padding: EdgeInsets.only(left: 8.0),
                              child: CircleAvatar(
                                backgroundColor: AppTheme.primaryIndigo,
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          // Loading indicator
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('AI is thinking...', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          // Input area
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      fillColor: AppTheme.backgroundDark,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppTheme.primaryIndigo, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      suffixIcon: _messageController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70),
                              onPressed: () {
                                _messageController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (value) {
                      setState(() {});
                    },
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  mini: true,
                  onPressed: _isLoading ? null : _sendMessage,
                  backgroundColor: Colors.blue[600],
                  disabledElevation: 0,
                  child: Icon(
                    Icons.send,
                    color: _isLoading ? Colors.grey : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
