import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/notification_service.dart';
import '../../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final bool isTherapist;

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    required this.isTherapist,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  final BackendApiService _backendApiService = BackendApiService();
  final List<Map<String, dynamic>> _messages = [];
  Timer? _pollTimer;
  String? _currentUserId;
  String _resolvedOtherUserName = '';
  String? _lastIncomingMessageId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = _authService.currentUserId;
    _resolvedOtherUserName = widget.otherUserName;
    _resolveOtherUserName();
    _loadConversation();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadConversation();
    });
  }

  Future<void> _resolveOtherUserName() async {
    final userById = _authService.getUserById(widget.otherUserId);
    if (userById != null && mounted) {
      setState(() {
        _resolvedOtherUserName =
            (userById['name'] ?? widget.otherUserName).toString();
      });
      return;
    }

    try {
      final patient = await _dbService.getPatient(widget.otherUserId);
      if (patient != null && mounted) {
        setState(() {
          _resolvedOtherUserName = patient.name;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppTheme.safeGreen,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.cardDark, width: 2),
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primaryIndigo,
                child: Text(
                  _resolvedOtherUserName.isNotEmpty
                      ? _resolvedOtherUserName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _resolvedOtherUserName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    widget.isTherapist ? 'Therapist' : 'Patient',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.forum_rounded,
                              size: 48,
                              color: AppTheme.primaryIndigo.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Start a conversation',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Send a message to begin',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];
                      final isUser = message['senderId'] == _currentUserId;
                      final isRead = (message['is_read'] as num?)?.toInt() ?? 0;
                      return _buildMessageBubble(
                        (message['body'] ?? '').toString(),
                        isUser,
                        _formatMessageTime(
                            (message['timestamp'] ?? '').toString()),
                        isReadByRecipient: isUser && isRead == 1,
                      );
                    },
                  ),
          ),
          // Input Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundDark,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        enabled: !_isLoading,
                        onSubmitted: !_isLoading ? (_) => _sendMessage() : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryIndigo,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryIndigo.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, bool isUser, String timestamp, {bool isReadByRecipient = false}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isUser ? 48 : 12,
          right: isUser ? 12 : 48,
          top: 4,
          bottom: 4,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.primaryIndigo : AppTheme.cardDark,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 10,
                        color: isUser
                            ? Colors.white.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timestamp,
                        style: TextStyle(
                          fontSize: 11,
                          color: isUser
                              ? Colors.white.withValues(alpha: 0.7)
                              : Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      if (isUser && isReadByRecipient) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle,
                          size: 12,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    final senderId = _currentUserId;
    if (message.isEmpty || senderId == null) return;

    final messageId = const Uuid().v4();
    final timestampIso = DateTime.now().toIso8601String();

    setState(() {
      _isLoading = true;
    });

    _messageController.clear();

    try {
      // Always save to local database first
      await _dbService.insertMessage(
        id: messageId,
        senderId: senderId,
        receiverId: widget.otherUserId,
        body: message,
        timestamp: timestampIso,
        status: 'sent',
      );

      // Try to sync with backend, but don't fail if it's not available
      await _backendApiService.sendMessage({
        'id': messageId,
        'senderId': senderId,
        'receiverId': widget.otherUserId,
        'senderName':
            (_authService.getCurrentUser()?['name'] ?? 'User').toString(),
        'receiverName': widget.otherUserName,
        'body': message,
        'timestamp': timestampIso,
        'status': 'sent',
      }).catchError((e) {
        print('Backend sync failed (continuing with local messaging): $e');
        return false;
      });

      // Only trigger AI fallback for explicit AI assistant conversations.
      final isAiConversation = widget.otherUserId == 'ai_assistant' ||
          widget.otherUserName.toLowerCase().contains('ai');
      if (!widget.isTherapist && isAiConversation) {
        try {
          // Initialize ChatService if not already done
          final chatService = ChatService();
          // Resolve backend URL
          final baseUrl = await _backendApiService.autoDetectLanBackendUrl() ??
              'http://localhost:5000';

          await chatService.initialize(
            baseUrl: baseUrl,
            userId: senderId,
            userRole: 'patient',
          );

          final result = await chatService.sendMessage(message);

          if (result['success'] == true) {
            final aiResponse =
                result['aiResponse'] ?? 'I understood your message.';
            final aiMessageId = const Uuid().v4();
            final aiTimestamp = DateTime.now().toIso8601String();

            await _dbService.insertMessage(
              id: aiMessageId,
              senderId: widget.otherUserId,
              receiverId: senderId,
              body: aiResponse,
              timestamp: aiTimestamp,
              status: 'sent',
            );
          }
        } catch (e) {
          print('AI response error (using local messaging only): $e');
          // Fallback: just wait for therapist response via direct messaging
        }
      }

      await _loadConversation();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
    }
  }

  Future<void> _loadConversation() async {
    _currentUserId = _authService.currentUserId;
    final userId = _currentUserId;
    if (userId == null) return;

    final local = await _dbService.getConversation(userId, widget.otherUserId);
    final remote =
        await _backendApiService.fetchConversation(userId, widget.otherUserId);

    for (final msg in remote) {
      await _dbService.insertMessage(
        id: (msg['id'] ?? const Uuid().v4()).toString(),
        senderId: (msg['senderId'] ?? '').toString(),
        receiverId: (msg['receiverId'] ?? '').toString(),
        body: (msg['body'] ?? '').toString(),
        timestamp:
            (msg['timestamp'] ?? DateTime.now().toIso8601String()).toString(),
        status: (msg['status'] ?? 'sent').toString(),
      );
    }

    final merged = remote.isNotEmpty
        ? await _dbService.getConversation(userId, widget.otherUserId)
        : local;

    await _dbService.markConversationAsRead(userId, widget.otherUserId);

    // Auto-mark MY messages (sent by current user) as read when recipient views conversation
    for (final msg in merged) {
      if ((msg['senderId'] ?? '') == userId) {
        final messageId = msg['id']?.toString() ?? '';
        final isRead = (msg['is_read'] as num?)?.toInt() ?? 0;
        if (messageId.isNotEmpty && isRead == 0) {
          await _backendApiService.markMessageRead(messageId);
        }
      }
    }

    if (mounted) {
      setState(() {
        _messages
          ..clear()
          ..addAll(merged);
      });
    }

    final incoming =
        merged.where((m) => m['senderId'] == widget.otherUserId).toList();
    if (incoming.isNotEmpty) {
      final newestIncoming = incoming.last;
      final newestId = newestIncoming['id']?.toString();
      if (newestId != null && _lastIncomingMessageId != newestId) {
        _lastIncomingMessageId = newestId;
        await NotificationService.showNewMessage(
          senderName: _resolvedOtherUserName,
          preview: (newestIncoming['body'] ?? '').toString(),
        );
      }
    }
  }

  String _getTimeString() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _formatMessageTime(String iso) {
    if (iso.isEmpty) return _getTimeString();
    try {
      final dt = DateTime.parse(iso);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:${dt.minute.toString().padLeft(2, '0')} $period';
    } catch (_) {
      return _getTimeString();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    super.dispose();
  }
}
