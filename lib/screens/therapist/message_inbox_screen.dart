import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import '../../core/theme/app_theme.dart';
import '../../services/chat_service.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../chat/chat_screen.dart';

class MessageInboxScreen extends StatefulWidget {
  const MessageInboxScreen({super.key});

  @override
  State<MessageInboxScreen> createState() => _MessageInboxScreenState();
}

class _MessageInboxScreenState extends State<MessageInboxScreen> {
  late final DatabaseService _dbService;
  late final AuthService _authService;
  StreamSubscription<List<Map<String, dynamic>>>? _cloudSub;

  List<Map<String, dynamic>> _patientThreads = [];
  Map<String, int> _unreadCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _dbService = DatabaseService();
    _authService = AuthService();
    _loadThreads();
    _startRealtimeUpdates();
  }

  Future<void> _loadThreads() async {
    try {
      final therapistId = _authService.currentUserId;
      if (therapistId == null) return;

      if (kIsWeb) {
        // On web, threads come from Firestore chats directly.
        final cloudThreads = await ChatService().fetchInbox(therapistId);
        final unreadMap = <String, int>{
          for (final t in cloudThreads)
            (t['patientId'] as String): (t['unreadCount'] as int? ?? 0),
        };
        if (mounted) {
          setState(() {
            _patientThreads = cloudThreads;
            _unreadCounts = unreadMap;
            _isLoading = false;
          });
        }
        return;
      }

      // Get all patients (local SQLite on mobile)
      final patients = await _dbService.getAllPatients();
      final threads = <Map<String, dynamic>>[];
      final unreadMap = <String, int>{};

      for (final patient in patients) {
        // Get last message from local SQLite (mobile)
        final messages = await _dbService.getConversation(therapistId, patient.id);
        if (messages.isNotEmpty) {
          final lastMessage = messages.last;
          
          // Count unread messages from patient
          final unreadCount = messages
              .where((m) => m['senderId'] == patient.id && m['status'] != 'read')
              .length;
          
          unreadMap[patient.id] = unreadCount;
          
          // Get last message sent by therapist to this patient for read status
          final lastTherapistMessage = messages
              .where((m) => m['senderId'] == therapistId)
              .toList()
              .reversed
              .firstWhere(
                (m) => true,
                orElse: () => <String, dynamic>{},
              );
          
          final lastTherapistRead = ((lastTherapistMessage['is_read'] ??
                  lastTherapistMessage['isRead'] ??
                  0) as num?)
              ?.toInt() ??
              0;
          
          threads.add({
            'patientId': patient.id,
            'patientName': patient.name,
            'patientEmail': patient.email,
            'lastMessage': (lastMessage['body'] ?? '').toString(),
            'lastMessageTime': DateTime.parse(
              (lastMessage['timestamp'] ?? DateTime.now().toIso8601String()).toString(),
            ),
            'messageCount': messages.length,
            'lastTherapistMessageRead': lastTherapistRead == 1,
          });
        }
      }

      // Sort by last message time
      threads.sort((a, b) => 
        (b['lastMessageTime'] as DateTime).compareTo(a['lastMessageTime'] as DateTime)
      );

      if (mounted) {
        setState(() {
          _patientThreads = threads;
          _unreadCounts = unreadMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading threads: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Subscribe to the Firestore conversation feed instead of polling. New
  /// messages update the parent `chats/{conversationId}` document, which
  /// re-emits the inbox and triggers a reload (reusing the SQLite/cloud
  /// load logic on each platform).
  void _startRealtimeUpdates() {
    final therapistId = _authService.currentUserId;
    if (therapistId == null) return;
    _cloudSub = ChatService()
        .inboxStream(therapistId)
        .listen((threads) {
          _loadThreads();
        }, onError: (e) {
          print('Inbox stream error: $e');
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💬 Message Inbox'),
        backgroundColor: AppTheme.cardDark,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _patientThreads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mail_outline,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No messages yet',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _patientThreads.length,
                  itemBuilder: (context, index) {
                    final thread = _patientThreads[index];
                    final unreadCount = _unreadCounts[thread['patientId']] ?? 0;
                    
                    return _buildThreadTile(
                      thread: thread,
                      unreadCount: unreadCount,
                      onTap: () => _openChat(thread),
                    );
                  },
                ),
    );
  }

  Widget _buildThreadTile({
    required Map<String, dynamic> thread,
    required int unreadCount,
    required VoidCallback onTap,
  }) {
    final lastTherapistRead = thread['lastTherapistMessageRead'] as bool? ?? false;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        border: Border.all(
          color: unreadCount > 0 
              ? AppTheme.primaryIndigo.withValues(alpha: 0.5)
              : Colors.grey[700]!,
          width: unreadCount > 0 ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryIndigo.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      (thread['patientName'] as String)[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              thread['patientName'] as String,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: unreadCount > 0 
                                    ? FontWeight.bold 
                                    : FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          // Read receipt indicator
                          Row(
                            children: [
                              if (lastTherapistRead)
                                const Row(
                                  children: [
                                    Icon(Icons.check_circle,
                                        size: 14,
                                        color: AppTheme.safeGreen),
                                    SizedBox(width: 4),
                                    Text('Read',
                                        style: TextStyle(
                                          color: AppTheme.safeGreen,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    Icon(Icons.circle_outlined,
                                        size: 14,
                                        color: Colors.white.withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Text('Sent',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ],
                                ),
                              if (unreadCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryIndigo,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (thread['lastMessage'] as String).length > 60
                            ? '${(thread['lastMessage'] as String).substring(0, 60)}...'
                            : thread['lastMessage'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 
                            unreadCount > 0 ? 0.8 : 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(thread['lastMessageTime'] as DateTime),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openChat(Map<String, dynamic> thread) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          otherUserId: thread['patientId'] as String,
          otherUserName: thread['patientName'] as String,
          isTherapist: true,
        ),
      ),
    ).then((_) {
      // Reload threads after chat closes
      _loadThreads();
    });
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }

  @override
  void dispose() {
    _cloudSub?.cancel();
    super.dispose();
  }
}
