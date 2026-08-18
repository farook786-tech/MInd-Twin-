import 'dart:convert';
import 'package:http/http.dart' as http;
import 'backend_api_service.dart';
import 'token_service.dart';

class GeminiService {
  final BackendApiService _apiService = BackendApiService();

  /// OpenRouter key provided at build time with
  /// `--dart-define=MINDTWIN_OPENROUTER_API_KEY=...`. Used as a direct
  /// fallback when the MindTwin backend is unreachable (e.g. web builds
  /// before the backend is deployed), so Ally still talks with a real LLM.
  /// No key is bundled with the app.
  static const String _openRouterApiKey = String.fromEnvironment(
    'MINDTWIN_OPENROUTER_API_KEY',
  );

  /// Reasonable cheap+smart model available on OpenRouter.
  static const String _openRouterModel =
      String.fromEnvironment('MINDTWIN_OPENROUTER_MODEL', defaultValue: 'openai/gpt-4o-mini');

  /// True when the bundled OpenRouter key is usable.
  bool get _hasOpenRouterKey =>
      _openRouterApiKey.isNotEmpty &&
      !_openRouterApiKey.startsWith('YOUR_') &&
      !_openRouterApiKey.startsWith('sk-or-v1-YOUR');

  Future<String> generateResponseAdvanced({
    required String systemPrompt,
    required String userPrompt,
    List<String>? history,
    int maxWords = 120,
  }) async {
    final prompt = userPrompt.toLowerCase();
    final isTherapist = systemPrompt.toLowerCase().contains('therapist');

    int? statusCode;

    try {
      final baseUrl =
          await _apiService.resolveBaseUrl() ?? 'http://localhost:5000';

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/gemini/chat'),
            headers: TokenService().getAuthHeaders(),
            body: jsonEncode({
              'prompt': userPrompt,
              'systemPrompt': systemPrompt,
              'history': history ?? [],
            }),
          )
          .timeout(const Duration(seconds: 20));

      statusCode = response.statusCode;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['response'] != null) {
          return data['response'].toString();
        }
      }
    } catch (_) {
      // Graceful offline fallback
    }

    // Patient-facing safety interceptor: when the backend is unreachable and
    // the caller is a patient, a crisis message always gets the safety
    // response (never routed to the raw model).
    if (!isTherapist &&
        (prompt.contains('crisis') ||
            prompt.contains('suicide') ||
            prompt.contains('self-harm') ||
            prompt.contains('kill myself'))) {
      return 'I hear you and I am here for you. Please reach out right now to a trusted person or local emergency crisis support (988).';
    }

    // Backend enforced its per-user rate limit (429) - do not burn direct
    // provider quota, respect the limit.
    if (statusCode == 429) {
      return 'I have reached the limit for AI messages for now. Please wait a little while and try again.';
    }

    // Direct OpenRouter fallback: backend was unreachable but we have a key,
    // so Ally still talks with a real LLM instead of canned text.
    if (_hasOpenRouterKey) {
      try {
        final response = await _callOpenRouter(
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          history: history ?? const [],
          maxWords: maxWords,
        );
        if (response != null && response.trim().isNotEmpty) {
          return response.trim();
        }
      } catch (_) {
        // Fall through to offline canned responses.
      }
    }

    if (isTherapist) {
      return 'Based on clinical context: validate patient emotion, introduce one grounding exercise, and monitor recent mood variance.';
    }

    return 'I am right here with you. Take one slow breath, ground yourself in this moment, and take one step at a time.';
  }

  /// Calls OpenRouter's OpenAI-compatible chat completions endpoint directly
  /// from the client. `history` entries are "role: message" strings.
  Future<String?> _callOpenRouter({
    required String systemPrompt,
    required String userPrompt,
    required List<String> history,
    required int maxWords,
  }) async {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    for (final entry in history) {
      final idx = entry.indexOf(': ');
      if (idx == -1) continue;
      final role = entry.substring(0, idx).trim().toLowerCase();
      final text = entry.substring(idx + 2).trim();
      if (text.isEmpty) continue;
      if (role == 'user' || role == 'assistant') {
        messages.add({'role': role, 'content': text});
      }
    }

    messages.add({'role': 'user', 'content': userPrompt});

    final response = await http
        .post(
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_openRouterApiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://mindtwin.app',
            'X-Title': 'MindTwin',
          },
          body: jsonEncode({
            'model': _openRouterModel,
            'messages': messages,
            'max_tokens': (maxWords * 1.5).round().clamp(100, 700).toInt(),
            'temperature': 0.7,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final content =
        (choices.first as Map<String, dynamic>)['message']?['content'];
    return content?.toString();
  }
}

/// Chat message model used by the AI chat screens.
class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String message;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.message,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? '',
      role: json['role'] ?? 'user',
      message: json['message'] ?? '',
      timestamp: DateTime.parse(
          json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Chat conversation model.
class ChatConversation {
  final String id;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime lastMessageAt;

  ChatConversation({
    required this.id,
    required this.messages,
    required this.createdAt,
    required this.lastMessageAt,
  });
}