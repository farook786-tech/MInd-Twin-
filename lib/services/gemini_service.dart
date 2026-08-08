import 'dart:convert';
import 'package:http/http.dart' as http;
import 'backend_api_service.dart';
import 'token_service.dart';

class GeminiService {
  final BackendApiService _apiService = BackendApiService();

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
      if (_apiService.isConfigured) {
        final manualUrl = await _apiService.getManualBaseUrl();
        final baseUrl = manualUrl ?? 'http://127.0.0.1:5000';

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
      }
    } catch (_) {
      // Graceful offline fallback
    }

    // Patient-facing safety interceptor: only when the backend is unreachable
    // AND the caller is not a therapist (therapist assistant must keep working).
    // Takes priority over the rate-limit notice so a crisis message still gets
    // the safety response.
    if (!isTherapist &&
        (prompt.contains('crisis') ||
            prompt.contains('suicide') ||
            prompt.contains('self-harm') ||
            prompt.contains('kill myself'))) {
      return 'I hear you and I am here for you. Please reach out right now to a trusted person or local emergency crisis support (988).';
    }

    // Backend enforced its per-user rate limit (429).
    if (statusCode == 429) {
      return 'I have reached the limit for AI messages for now. Please wait a little while and try again.';
    }

    if (isTherapist) {
      return 'Based on clinical context: validate patient emotion, introduce one grounding exercise, and monitor recent mood variance.';
    }

    return 'I am right here with you. Take one slow breath, ground yourself in this moment, and take one step at a time.';
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