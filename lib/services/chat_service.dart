import 'package:http/http.dart' as http;
import 'dart:convert';

/// Chat message model
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
      timestamp: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Chat conversation model
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

/// Chat service - handles communication with backend LLM API
class ChatService {
  static final ChatService _instance = ChatService._internal();
  
  late String _baseUrl;
  late String _userId;
  late String _userRole;
  String? _currentConversationId;

  factory ChatService() {
    return _instance;
  }

  ChatService._internal();

  /// Initialize the service
  Future<void> initialize({
    required String baseUrl,
    required String userId,
    required String userRole,
  }) async {
    _baseUrl = baseUrl;
    _userId = userId;
    _userRole = userRole;
  }

  /// Send a message and get AI response
  Future<Map<String, dynamic>> sendMessage(
    String messageText, {
    Map<String, dynamic>? context,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/chat/message'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _userId,
          'userRole': _userRole,
          'message': messageText,
          'conversationId': _currentConversationId,
          'context': context ?? {},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentConversationId = data['conversationId'];
        
        return {
          'success': true,
          'conversationId': data['conversationId'],
          'aiResponse': data['aiResponse'],
          'tokensUsed': data['tokensUsed'],
          'remainingBudget': data['remainingBudget'],
        };
      } else if (response.statusCode == 429) {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'error': data['error'] ?? 'Rate limited or token budget exceeded',
          'tokenBudget': data['tokenBudget'],
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to send message: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Get conversation history
  Future<List<ChatMessage>> getConversationHistory(String conversationId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/chat/conversation/$conversationId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = (data['messages'] as List)
            .map((msg) => ChatMessage.fromJson(msg))
            .toList();
        return messages;
      } else {
        return [];
      }
    } catch (e) {
      print('Error fetching conversation history: $e');
      return [];
    }
  }

  /// Get all conversations for user
  Future<List<Map<String, dynamic>>> getUserConversations() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/chat/conversations/$_userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['conversations'] ?? []);
      } else {
        return [];
      }
    } catch (e) {
      print('Error fetching conversations: $e');
      return [];
    }
  }

  /// Get token usage status
  Future<Map<String, dynamic>> getTokenStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/chat/tokens/status'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['tokenStatus'] ?? {};
      } else {
        return {};
      }
    } catch (e) {
      print('Error fetching token status: $e');
      return {};
    }
  }

  /// Get current conversation ID
  String? get currentConversationId => _currentConversationId;

  /// Set conversation ID (for loading existing conversations)
  void setConversationId(String conversationId) {
    _currentConversationId = conversationId;
  }

  /// Clear current conversation
  void clearConversation() {
    _currentConversationId = null;
  }
}
