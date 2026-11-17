import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/chat_service.dart';
import '../../services/gemini_service.dart' show GeminiService;
import '../../services/notification_router.dart';
import '../../services/notification_service.dart';

/// Real-time patient <-> therapist conversation backed by Firestore.
///
/// [isTherapist] is true when the CURRENT user is the therapist. The actual
/// relationship is re-verified via [ChatService.resolvePeer] before any
/// message is shown or sent.
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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();

  ChatPeer? _peer;
  String? _accessError;
  bool _resolving = true;

  StreamSubscription<List<ChatMessage>>? _sub;
  List<ChatMessage> _messages = const [];
  bool _streamLoaded = false;
  String? _streamError;

  /// Ids already submitted for read-marking (avoids duplicate writes).
  final Set<String> _markedRead = {};
  bool _unreadResetDone = false;

  /// Messages whose server write was rejected (e.g. permission denied).
  final Map<String, String> _failed = {};

  bool _appResumed = true;

  // In-memory session for the AI assistant pseudo-conversation (only when
  // otherUserId == ChatService.aiAssistantId; never stored in Firestore).
  final List<ChatMessage> _aiMessages = [];
  bool _aiBusy = false;

  bool get _isAi => widget.otherUserId == ChatService.aiAssistantId;
  String? get _chatId => _peer?.chatId;
  String get _otherName {
    final resolved = _peer?.otherName;
    if (resolved != null && resolved.isNotEmpty) return resolved;
    if (widget.otherUserName.isNotEmpty) return widget.otherUserName;
    return _isAi ? 'AI Assistant' : 'Contact';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _appResumed = state == null || state == AppLifecycleState.resumed;
    if (_isAi) {
      _resolving = false;
      _streamLoaded = true;
    } else {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _resolving = true;
      _accessError = null;
    });
    try {
      final peer = await _chatService.resolvePeer(widget.otherUserId);
      if (!mounted) return;
      setState(() {
        _peer = peer;
        _resolving = false;
      });
      if (_appResumed) NotificationRouter.activeChatId = peer.chatId;
      unawaited(NotificationService.cancelChat(peer.chatId));
      _subscribe(peer.chatId);
    } on ChatAccessException catch (e) {
      if (!mounted) return;
      setState(() {
        _accessError = e.message;
        _resolving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _accessError = 'Could not open this conversation: $e';
        _resolving = false;
      });
    }
  }

  void _subscribe(String chatId) {
    _sub?.cancel();
    _sub = _chatService.messagesStream(chatId).listen((messages) {
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _streamLoaded = true;
        _streamError = null;
      });
      _markIncomingRead();
    }, onError: (Object e) {
      debugPrint('Chat stream error: $e');
      if (!mounted) return;
      setState(() {
        _streamLoaded = true;
        _streamError = 'Unable to load messages. $e';
      });
    });
  }

  /// Mark incoming messages read and reset my unread counter, only while the
  /// conversation is actually visible (app resumed).
  void _markIncomingRead() {
    final peer = _peer;
    if (peer == null || !_appResumed || _messages.isEmpty) return;
    final ids = _messages
        .where((m) =>
            m.receiverId == peer.myUid &&
            m.senderId == peer.otherUid &&
            !m.read &&
            !_markedRead.contains(m.id))
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty && _unreadResetDone) return;
    _markedRead.addAll(ids);
    _unreadResetDone = true;
    _chatService
        .markRead(chatId: peer.chatId, myUid: peer.myUid, messageIds: ids)
        .catchError((Object e) {
      debugPrint('markRead failed: $e');
      _markedRead.removeAll(ids); // retry on next snapshot
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final chatId = _chatId;
    switch (state) {
      case AppLifecycleState.resumed:
        _appResumed = true;
        if (chatId != null) {
          NotificationRouter.activeChatId = chatId;
          unawaited(NotificationService.cancelChat(chatId));
        }
        _markIncomingRead();
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appResumed = false;
        if (chatId != null && NotificationRouter.activeChatId == chatId) {
          NotificationRouter.activeChatId = null;
        }
        break;
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (text.length > ChatService.maxMessageLength) {
      _showSnack(
          'Message is too long (max ${ChatService.maxMessageLength} characters).');
      return;
    }
    if (_isAi) {
      _messageController.clear();
      _sendToAi(text);
      return;
    }
    final peer = _peer;
    if (peer == null) return;

    _messageController.clear();
    try {
      final result = _chatService.sendMessage(peer: peer, text: text);
      // Not awaited: offline the write is queued by Firestore and the
      // bubble shows a "sending" clock until the server confirms.
      result.committed.catchError((Object e) {
        debugPrint('Message ${result.messageId} rejected: $e');
        if (!mounted) return;
        setState(() => _failed[result.messageId] = e.toString());
        _showSnack('Message could not be delivered.');
      });
    } catch (e) {
      _messageController.text = text;
      _showSnack('Could not send message: $e');
    }
  }

  Future<void> _sendToAi(String text) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'me';
    final now = DateTime.now();
    setState(() {
      _aiMessages.add(ChatMessage(
        id: 'local_${now.microsecondsSinceEpoch}',
        senderId: myUid,
        receiverId: ChatService.aiAssistantId,
        senderName: '',
        text: text,
        createdAt: now,
        pending: false,
        read: true,
      ));
      _aiBusy = true;
    });
    String reply;
    try {
      reply = await GeminiService().generateResponseAdvanced(
        systemPrompt: 'You are a supportive mental health AI assistant.',
        userPrompt: text,
      );
    } catch (e) {
      reply = 'The AI assistant is unavailable right now. '
          'If you are in crisis, contact your therapist or local emergency services.';
    }
    if (!mounted) return;
    final at = DateTime.now();
    setState(() {
      _aiBusy = false;
      _aiMessages.add(ChatMessage(
        id: 'ai_${at.microsecondsSinceEpoch}',
        senderId: ChatService.aiAssistantId,
        receiverId: myUid,
        senderName: 'AI Assistant',
        text: reply,
        createdAt: at,
        pending: false,
        read: true,
      ));
    });
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String get _subtitle {
    if (_isAi) return 'AI assistant';
    final iAmTherapist = _peer?.iAmTherapist ?? widget.isTherapist;
    return iAmTherapist ? 'Patient' : 'Your therapist';
  }

  @override
  Widget build(BuildContext context) {
    final name = _otherName;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.primaryIndigo,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
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
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    _subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.ink.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_isAi && _aiBusy)
            const LinearProgressIndicator(minHeight: 2),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_resolving) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_accessError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 48, color: AppColors.ink.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text(
                _accessError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.ink, fontSize: 15),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _start, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (!_streamLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_streamError != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _streamError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.ink.withValues(alpha: 0.7)),
          ),
        ),
      );
    }

    final messages = _isAi ? _aiMessages : _messages;
    if (messages.isEmpty) return _buildEmptyState();

    final myUid = _peer?.myUid ?? FirebaseAuth.instance.currentUser?.uid;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final i = messages.length - 1 - index;
        final message = messages[i];
        final showDay = i == 0 ||
            !_sameDay(messages[i - 1].displayTime, message.displayTime);
        final bubble = _buildMessageBubble(message, message.senderId == myUid);
        if (!showDay) return bubble;
        return Column(
          children: [_buildDayDivider(message.displayTime), bubble],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
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
            Text(
              'Start a conversation',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to begin',
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayDivider(DateTime time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        _dayLabel(time),
        style: TextStyle(
          fontSize: 12,
          color: AppColors.ink.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildInput() {
    final canSend = _isAi ? !_aiBusy : (_peer != null);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        border: Border(
          top: BorderSide(color: AppColors.ink.withValues(alpha: 0.1), width: 1),
        ),
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
                    color: AppColors.ink.withValues(alpha: 0.1),
                  ),
                ),
                child: TextField(
                  controller: _messageController,
                  style: TextStyle(color: AppColors.ink),
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(
                      color: AppColors.ink.withValues(alpha: 0.4),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  enabled: canSend,
                  onSubmitted: canSend ? (_) => _sendMessage() : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: canSend ? _sendMessage : null,
                icon: const Icon(Icons.send_rounded, size: 20),
                color: AppColors.ink,
                tooltip: 'Send',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMine) {
    final faded = AppColors.ink.withValues(alpha: isMine ? 0.7 : 0.5);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMine ? 48 : 12,
          right: isMine ? 12 : 48,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMine ? AppTheme.primaryIndigo : AppTheme.cardDark,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          border: isMine
              ? null
              : Border.all(color: AppColors.ink.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat.jm().format(message.displayTime),
                  style: TextStyle(fontSize: 11, color: faded),
                ),
                if (isMine && !_isAi) ...[
                  const SizedBox(width: 6),
                  _buildStatusIcon(message),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// failed (!) / sending (clock) / sent (single tick) / read (double tick).
  Widget _buildStatusIcon(ChatMessage message) {
    if (_failed.containsKey(message.id)) {
      return Tooltip(
        message: 'Not delivered',
        child: Icon(Icons.error_outline, size: 14, color: AppTheme.riskRed),
      );
    }
    if (message.pending) {
      return Tooltip(
        message: 'Sending',
        child: Icon(Icons.schedule_rounded,
            size: 13, color: AppColors.ink.withValues(alpha: 0.7)),
      );
    }
    if (message.read) {
      return const Tooltip(
        message: 'Read',
        child: Icon(Icons.done_all_rounded,
            size: 15, color: Colors.lightBlueAccent),
      );
    }
    return Tooltip(
      message: 'Sent',
      child: Icon(Icons.done_rounded,
          size: 15, color: AppColors.ink.withValues(alpha: 0.7)),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    if (_sameDay(t, now)) return 'Today';
    if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    if (t.year == now.year) return DateFormat.MMMd().format(t);
    return DateFormat.yMMMd().format(t);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final chatId = _chatId;
    if (chatId != null && NotificationRouter.activeChatId == chatId) {
      NotificationRouter.activeChatId = null;
    }
    _sub?.cancel();
    _messageController.dispose();
    super.dispose();
  }
}
