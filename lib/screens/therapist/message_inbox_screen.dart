import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/chat_service.dart';
import '../chat/chat_screen.dart';

/// Therapist inbox, built live from Firestore on every platform:
/// `chats where participants array-contains myUid orderBy lastMessageAt desc`.
class MessageInboxScreen extends StatefulWidget {
  const MessageInboxScreen({super.key});

  @override
  State<MessageInboxScreen> createState() => _MessageInboxScreenState();
}

class _MessageInboxScreenState extends State<MessageInboxScreen> {
  String? _myUid;
  Stream<List<ChatThread>>? _stream;

  /// Fallback names for chats whose `names` map lacks the other participant
  /// (legacy chats). Looked up once per uid from users/{uid}.
  final Map<String, Future<String?>> _nameLookups = {};

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid;
    final uid = _myUid;
    if (uid != null) _stream = ChatService().inboxStream(uid);
  }

  Future<String?> _lookupName(String uid) {
    return _nameLookups.putIfAbsent(uid, () async {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final name = doc.data()?['name']?.toString().trim();
        return (name == null || name.isEmpty) ? null : name;
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Inbox'),
        backgroundColor: AppTheme.cardDark,
      ),
      body: _stream == null
          ? _buildMessage(Icons.lock_outline, 'Please sign in to view messages')
          : StreamBuilder<List<ChatThread>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  debugPrint('Inbox stream error: ${snapshot.error}');
                  return _buildMessage(
                    Icons.error_outline,
                    'Unable to load messages.\n${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final threads = snapshot.data!;
                if (threads.isEmpty) {
                  return _buildMessage(Icons.mail_outline, 'No messages yet');
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: threads.length,
                  itemBuilder: (context, index) =>
                      _buildThreadTile(threads[index]),
                );
              },
            ),
    );
  }

  Widget _buildMessage(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadTile(ChatThread thread) {
    final known = thread.otherUserName;
    if (known != null) return _threadTile(thread, known);
    return FutureBuilder<String?>(
      future: _lookupName(thread.otherUserId),
      builder: (context, snap) =>
          _threadTile(thread, snap.data ?? 'Patient'),
    );
  }

  Widget _threadTile(ChatThread thread, String name) {
    final unread = thread.unreadForMe;
    final lastIsMine = thread.lastSenderId == _myUid;
    final preview =
        lastIsMine ? 'You: ${thread.lastMessage}' : thread.lastMessage;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        border: Border.all(
          color: unread > 0
              ? AppTheme.primaryIndigo.withValues(alpha: 0.5)
              : Colors.grey[700]!,
          width: unread > 0 ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openChat(thread, name),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryIndigo.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: unread > 0
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          if (lastIsMine) _buildReceipt(thread),
                          if (unread > 0) ...[
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
                                unread > 99 ? '99+' : unread.toString(),
                                style: TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.ink
                              .withValues(alpha: unread > 0 ? 0.85 : 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(thread.lastMessageAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.ink.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Read" once the patient's unread counter is back to 0.
  Widget _buildReceipt(ChatThread thread) {
    final read = thread.unreadForOther == 0;
    final color =
        read ? AppTheme.safeGreen : AppColors.ink.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(read ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          read ? 'Read' : 'Sent',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _openChat(ChatThread thread, String name) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => ChatScreen(
          otherUserId: thread.otherUserId,
          otherUserName: name,
          isTherapist: true,
        ),
      ),
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return 'Sending…';
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day) {
      return DateFormat.jm().format(dateTime);
    }
    if (difference.inDays < 7) return DateFormat.E().add_jm().format(dateTime);
    return DateFormat.yMMMd().format(dateTime);
  }
}
