import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../services/gemini_service.dart';

class TherapistAIChatScreen extends StatefulWidget {
  final String therapistId;
  final String patientId;
  final String patientName;

  const TherapistAIChatScreen({
    super.key,
    required this.therapistId,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<TherapistAIChatScreen> createState() => _TherapistAIChatScreenState();
}

class _TherapistAIChatScreenState extends State<TherapistAIChatScreen> {
  final GeminiService _geminiService = GeminiService();
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
      id: 'therapist_welcome_${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      message:
        'I am your AI clinical assistant. Ask about assessment, intervention strategy, risk interpretation, or session planning.',
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    // Add therapist message to UI
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
          'You are an AI clinical assistant helping therapists. '
          'Summarise evidence and suggest clinical workflow steps only. Never recommend, name, '
          'start, stop or adjust a specific medication or dose; say that medication decisions '
          'require assessment by the treating psychiatrist. You do not diagnose. '
          'Be concise and professional. '
          'Keep responses under 150 words.',
        userPrompt:
          'Patient: ${widget.patientName} (${widget.patientId}). Therapist question: $messageText',
        history: history.take(8).toList(),
        maxWords: 150,
      );

      setState(() {
        _messages.add(ChatMessage(
          id: DateTime.now().toString(),
          role: 'assistant',
          message: aiText,
          timestamp: DateTime.now(),
        ));
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Clinical assistant is unavailable right now. Please try again shortly.';
      });
    } finally {
      setState(() {
        _isLoading = false;
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
        title: Text('Clinical Assistant - ${widget.patientName}'),
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
                  Icon(Icons.error_outline, color: AppTheme.riskRed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: AppColors.ink),
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
                        Icon(Icons.psychology, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Clinical AI Assistant',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppColors.ink,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Text(
                            'Ask questions about patient assessment, treatment planning, or clinical insights.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.ink.withValues(alpha: 0.7)),
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
                      final isTherapist = message.role == 'user';

                      return Row(
                        mainAxisAlignment: isTherapist
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!isTherapist)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: CircleAvatar(
                                backgroundColor: Colors.purple[100],
                                child: Icon(Icons.psychology, color: Colors.purple[700]),
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
                                color: isTherapist ? Colors.blue[600] : AppTheme.cardDark,
                                border: !isTherapist ? Border.all(color: AppColors.ink.withValues(alpha: 0.1)) : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: isTherapist
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.message,
                                    style: TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 15,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('HH:mm').format(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isTherapist
                                          ? AppColors.ink70
                                          : AppColors.ink54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isTherapist)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: CircleAvatar(
                                backgroundColor: Colors.blue[300],
                                child: Icon(Icons.person, color: AppColors.ink),
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
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.purple[600]!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('AI is analyzing...', style: TextStyle(color: AppColors.ink70)),
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
                top: BorderSide(color: AppColors.ink.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: TextStyle(color: AppColors.ink),
                    decoration: InputDecoration(
                      hintText: 'Ask about treatment, assessment, or interventions...',
                      hintStyle: TextStyle(color: AppColors.ink.withValues(alpha: 0.5)),
                      fillColor: AppTheme.backgroundDark,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppColors.ink.withValues(alpha: 0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppColors.ink.withValues(alpha: 0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppTheme.primaryIndigo, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      prefixIcon: Icon(Icons.search, color: AppColors.ink70),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                    minLines: 1,
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
                  backgroundColor: Colors.purple[600],
                  disabledElevation: 0,
                  child: Icon(
                    Icons.send,
                    color: _isLoading ? Colors.grey : AppColors.ink,
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
