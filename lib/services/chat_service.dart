import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

/// Firestore-backed messaging that works on every platform (including web,
/// where the local SQLite database and the optional backend API are both
/// unavailable). Messages are stored per conversation pair under:
///   chats/{conversationId}/messages/{messageId}
class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  /// Canonical, order-independent id for a two-party conversation.
  String conversationId(String userA, String userB) {
    final ids = [userA, userB]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  CollectionReference<Map<String, dynamic>> _messagesRef(String userA, String userB) {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(conversationId(userA, userB))
        .collection('messages');
  }

  /// Persist a message and ensure the conversation document exists so the
  /// participant list can be queried by the inbox.
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String body,
  }) async {
    final messageId = const Uuid().v4();
    final now = DateTime.now().toUtc();

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(conversationId(senderId, receiverId))
        .set(
          {
            'participants': [senderId, receiverId],
            'lastMessageAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

    await _messagesRef(senderId, receiverId).doc(messageId).set({
      'id': messageId,
      'senderId': senderId,
      'receiverId': receiverId,
      'body': body,
      'timestamp': now.toIso8601String(),
      'status': 'sent',
      'is_read': 0,
      'isRead': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> conversationStream(String userA, String userB) {
    return _messagesRef(userA, userB)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()).toList());
  }

  Future<List<Map<String, dynamic>>> fetchConversation(String userA, String userB) async {
    final snap = await _messagesRef(userA, userB).orderBy('createdAt').get();
    return snap.docs.map((doc) => doc.data()).toList();
  }

  /// Mark every incoming unread message addressed to [myId] as read.
  Future<void> markRead(String userA, String userB, String myId) async {
    final snap = await _messagesRef(userA, userB)
        .where('receiverId', isEqualTo: myId)
        .where('is_read', isEqualTo: 0)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'is_read': 1, 'isRead': 1});
    }
    await batch.commit();
  }

  /// All conversations a user participates in, with their latest message.
  Future<List<Map<String, dynamic>>> fetchInbox(String myId) async {
    final chats = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myId)
        .get();

    final threads = <Map<String, dynamic>>[];
    for (final chat in chats.docs) {
      final data = chat.data();
      final participants = (data['participants'] as List? ?? const [])
          .whereType<String>()
          .toList();
      final otherId = participants.where((p) => p != myId).firstOrNull;
      if (otherId == null) continue;

      final messagesSnap = await chat.reference
          .collection('messages')
          .orderBy('createdAt')
          .get();
      final messages = messagesSnap.docs.map((d) => d.data()).toList();
      if (messages.isEmpty) continue;

      final lastMessage = messages.last;
      final unreadCount = messages
          .where((m) =>
              m['senderId'] == otherId && (m['is_read'] ?? 0) == 0)
          .length;

      threads.add({
        'patientId': otherId,
        'patientName': data['otherName'] ?? _guessName(lastMessage),
        'lastMessage': (lastMessage['body'] ?? '').toString(),
        'lastMessageTime': _parseTimestamp(lastMessage),
        'messageCount': messages.length,
        'unreadCount': unreadCount,
        'lastTherapistMessageRead': true,
      });
    }

    threads.sort((a, b) =>
        (b['lastMessageTime'] as DateTime).compareTo(a['lastMessageTime'] as DateTime));
    return threads;
  }

  /// Real-time version of [fetchInbox]: emits an updated thread list whenever
  /// a conversation document changes (new message, participant update, etc.).
  Stream<List<Map<String, dynamic>>> inboxStream(String myId) {
    return FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myId)
        .snapshots()
        .asyncMap((snap) async {
      final threads = <Map<String, dynamic>>[];
      for (final chat in snap.docs) {
        final data = chat.data();
        final participants = (data['participants'] as List? ?? const [])
            .whereType<String>()
            .toList();
        final otherId = participants.where((p) => p != myId).firstOrNull;
        if (otherId == null) continue;

        final messagesSnap = await chat.reference
            .collection('messages')
            .orderBy('createdAt')
            .get();
        final messages = messagesSnap.docs.map((d) => d.data()).toList();
        if (messages.isEmpty) continue;

        final lastMessage = messages.last;
        final unreadCount = messages
            .where((m) =>
                m['senderId'] == otherId && (m['is_read'] ?? 0) == 0)
            .length;

        threads.add({
          'patientId': otherId,
          'patientName': data['otherName'] ?? _guessName(lastMessage),
          'lastMessage': (lastMessage['body'] ?? '').toString(),
          'lastMessageTime': _parseTimestamp(lastMessage),
          'messageCount': messages.length,
          'unreadCount': unreadCount,
          'lastTherapistMessageRead': true,
        });
      }

      threads.sort((a, b) =>
          (b['lastMessageTime'] as DateTime).compareTo(a['lastMessageTime'] as DateTime));
      return threads;
    });
  }

  /// Record the display name of a conversation partner so the inbox can show
  /// it without extra lookups.
  Future<void> setOtherName({
    required String myId,
    required String otherId,
    required String name,
  }) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(conversationId(myId, otherId))
        .set(
          {'otherName': name},
          SetOptions(merge: true),
        );
  }

  String _guessName(Map<String, dynamic> message) {
    final id = message['senderId']?.toString() ?? '';
    if (id.isEmpty) return 'Patient';
    return id.length >= 8 ? id.substring(0, 8) : id;
  }

  DateTime _parseTimestamp(Map<String, dynamic> message) {
    final raw = (message['timestamp'] ?? '').toString();
    return DateTime.tryParse(raw)?.toLocal() ??
        (message['createdAt'] is Timestamp
            ? (message['createdAt'] as Timestamp).toDate()
            : DateTime.now());
  }
}
