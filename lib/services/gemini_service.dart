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

    // Offline safety interceptor
    if (prompt.contains('crisis') || prompt.contains('suicide') || prompt.contains('self-harm')) {
      return isTherapist
          ? '[CRITICAL SAFETY ALERT] Crisis signals detected. Priority safety contact required.'
          : 'I hear you and I am here for you. Please reach out right now to a trusted person or local emergency crisis support (988).';
    }

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

    if (isTherapist) {
      return 'Based on clinical context: validate patient emotion, introduce one grounding exercise, and monitor recent mood variance.';
    }

    return 'I am right here with you. Take one slow breath, ground yourself in this moment, and take one step at a time.';
  }
}