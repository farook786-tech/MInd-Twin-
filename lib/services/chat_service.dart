import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Thrown when the current user may not chat with the requested person, or
/// the relationship cannot be verified.
class ChatAccessException implements Exception {
  final String message;
  const ChatAccessException(this.message);
  @override
  String toString() => message;
}

/// The two parties of a verified conversation.
class ChatPeer {
  final String myUid;
  final String myName;
  final String otherUid;
  final String otherName;
  final bool iAmTherapist;

  const ChatPeer({
    required this.myUid,
    required this.myName,
    required this.otherUid,
    required this.otherName,
    required this.iAmTherapist,
  });

  String get chatId => ChatService.chatIdFor(myUid, otherUid);
}

class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String senderName;
  final String text;

  /// Server time converted to the device's local time zone; null while the
  /// server timestamp is still pending.
  final DateTime? createdAt;

  /// Local write not yet acknowledged by the server (offline / in flight).
  final bool pending;
  final bool read;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.senderName,
    required this.text,
    required this.createdAt,
    required this.pending,
    required this.read,
  });

  factory ChatMessage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? created;
    final raw = data['createdAt'];
    if (raw is Timestamp) {
      created = raw.toDate().toLocal();
    } else if (data['timestamp'] is String) {
      // Legacy messages stored an ISO string.
      created = DateTime.tryParse(data['timestamp'] as String)?.toLocal();
    }
    return ChatMessage(
      id: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      receiverId: (data['receiverId'] ?? '').toString(),
      senderName: (data['senderName'] ?? '').toString(),
      text: (data['text'] ?? data['body'] ?? '').toString(),
      createdAt: created,
      pending: doc.metadata.hasPendingWrites,
      read: data['read'] == true ||
          data['is_read'] == 1 ||
          data['isRead'] == 1,
    );
  }

  /// Best available display time: the server time or, for a pending write,
  /// the local time at which it was sent (estimate).
  DateTime get displayTime =>
      createdAt ?? ChatService._localSendTimes[id] ?? DateTime.now();
}

class ChatThread {
  final String chatId;
  final String otherUserId;

  /// From the chat doc's `names` map; null when not yet known.
  final String? otherUserName;
  final String lastMessage;
  final String lastSenderId;
  final DateTime? lastMessageAt;
  final int unreadForMe;
  final int unreadForOther;

  const ChatThread({
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    required this.lastMessage,
    required this.lastSenderId,
    required this.lastMessageAt,
    required this.unreadForMe,
    required this.unreadForOther,
  });
}

/// Firestore-backed patient <-> therapist messaging (docs/DATA_MODEL.md).
///
/// Firestore (with offline persistence) is the single source of truth: no
/// backend send, no SQLite copy. Push notifications for new messages are sent
/// by the `onMessageCreated` Cloud Function.
class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  /// Pseudo user id of the in-app AI assistant (never stored in Firestore).
  static const String aiAssistantId = 'ai_assistant';

  static const int maxMessageLength = 4000;

  /// Local send time per pending message id, used as a display/ordering
  /// estimate until the server timestamp arrives.
  static final Map<String, DateTime> _localSendTimes = {};

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Canonical chat id: `sorted([uidA, uidB]).join('__')`.
  static String chatIdFor(String userA, String userB) {
    final ids = [userA, userB]..sort();
    return ids.join('__');
  }

  DocumentReference<Map<String, dynamic>> chatRef(String chatId) =>
      _db.collection('chats').doc(chatId);

  CollectionReference<Map<String, dynamic>> messagesRef(String chatId) =>
      chatRef(chatId).collection('messages');

  /// Verifies that the signed-in user may chat with [otherUid] and resolves
  /// both display names from authoritative sources:
  /// * patient: only with `users/{me}.therapistId`; name = `therapistName`.
  /// * therapist: only with a patient whose `therapistId == me`.
  Future<ChatPeer> resolvePeer(String otherUid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      throw const ChatAccessException('Please sign in to use messaging.');
    }
    if (otherUid.isEmpty || otherUid == me.uid) {
      throw const ChatAccessException('Invalid conversation.');
    }

    String? role;
    try {
      // Cached token is fine (works offline); claims are the trusted role.
      final token = await me.getIdTokenResult();
      role = token.claims?['role']?.toString();
    } catch (_) {}

    DocumentSnapshot<Map<String, dynamic>> myDoc;
    try {
      myDoc = await _db.collection('users').doc(me.uid).get();
    } catch (_) {
      throw const ChatAccessException(
          'Could not verify your account. Check your connection and retry.');
    }
    final myData = myDoc.data() ?? const <String, dynamic>{};
    role ??= myData['role']?.toString();
    final myName = _nonEmpty(myData['name']) ??
        _nonEmpty(me.displayName) ??
        (role == 'therapist' ? 'Therapist' : 'Patient');

    if (role == 'patient') {
      final therapistId = _nonEmpty(myData['therapistId']);
      if (therapistId == null) {
        throw const ChatAccessException(
            'You are not linked to a therapist yet.');
      }
      if (therapistId != otherUid) {
        throw const ChatAccessException(
            'You can only message your own therapist.');
      }
      return ChatPeer(
        myUid: me.uid,
        myName: myName,
        otherUid: otherUid,
        otherName: _nonEmpty(myData['therapistName']) ?? 'Your therapist',
        iAmTherapist: false,
      );
    }

    if (role == 'therapist') {
      DocumentSnapshot<Map<String, dynamic>> patientDoc;
      try {
        patientDoc = await _db.collection('users').doc(otherUid).get();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw const ChatAccessException(
              'This patient is not assigned to you.');
        }
        throw const ChatAccessException(
            'Could not verify this patient. Check your connection and retry.');
      } catch (_) {
        throw const ChatAccessException(
            'Could not verify this patient. Check your connection and retry.');
      }
      final patient = patientDoc.data();
      if (patient == null || patient['therapistId'] != me.uid) {
        throw const ChatAccessException(
            'This patient is not assigned to you.');
      }
      return ChatPeer(
        myUid: me.uid,
        myName: myName,
        otherUid: otherUid,
        otherName: _nonEmpty(patient['name']) ?? 'Patient',
        iAmTherapist: true,
      );
    }

    if (role == 'therapist_pending') {
      throw const ChatAccessException(
          'Messaging is available once your therapist account is approved.');
    }
    throw const ChatAccessException('Your account cannot use messaging.');
  }

  /// Live messages of a conversation, oldest first. Includes metadata
  /// changes so pending -> sent transitions and read receipts re-render.
  /// Pending server timestamps sort after confirmed ones (Firestore local
  /// ordering), so newly sent messages appear at the bottom.
  Stream<List<ChatMessage>> messagesStream(String chatId, {int limit = 500}) {
    return messagesRef(chatId)
        .orderBy('createdAt')
        .limitToLast(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList());
  }

  /// Writes the message and updates the chat doc atomically in ONE batch.
  /// Returns immediately with the message id; `committed`
  /// completes when the server acknowledges (never awaited by the UI, since
  /// it does not complete while offline — Firestore queues the write).
  ({String messageId, Future<void> committed}) sendMessage({
    required ChatPeer peer,
    required String text,
  }) {
    final body = text.trim();
    if (body.isEmpty) {
      throw ArgumentError('Message is empty');
    }
    if (body.length > maxMessageLength) {
      throw ArgumentError('Message is too long');
    }
    final chatId = peer.chatId;
    final msgRef = messagesRef(chatId).doc();
    final messageId = msgRef.id;
    _localSendTimes[messageId] = DateTime.now();

    final participants = [peer.myUid, peer.otherUid]..sort();
    final names = <String, String>{peer.myUid: peer.myName};
    if (peer.otherName.isNotEmpty) names[peer.otherUid] = peer.otherName;

    final batch = _db.batch();
    batch.set(msgRef, {
      'id': messageId,
      'senderId': peer.myUid,
      'receiverId': peer.otherUid,
      'senderName': peer.myName,
      'text': body,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
    batch.set(
      chatRef(chatId),
      {
        'participants': participants,
        'names': names,
        'lastMessage': body.length > 200 ? '${body.substring(0, 200)}…' : body,
        'lastSenderId': peer.myUid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unread': {peer.otherUid: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );

    final committed = batch.commit().whenComplete(() {
      _localSendTimes.remove(messageId);
    });
    return (messageId: messageId, committed: committed);
  }

  /// Marks [messageIds] (incoming messages addressed to [myUid]) as read and
  /// resets `unread.{myUid}` to 0, in one batch. Not awaited by the UI.
  Future<void> markRead({
    required String chatId,
    required String myUid,
    required Iterable<String> messageIds,
  }) {
    final batch = _db.batch();
    final ref = messagesRef(chatId);
    for (final id in messageIds) {
      batch.update(ref.doc(id), {'read': true});
    }
    // Firebase Auth uids are alphanumeric, so the dotted path is safe.
    batch.update(chatRef(chatId), {'unread.$myUid': 0});
    return batch.commit();
  }

  /// Live inbox: every chat I participate in, newest first.
  /// Requires composite index chats(participants ARRAY_CONTAINS,
  /// lastMessageAt DESC).
  Stream<List<ChatThread>> inboxStream(String myUid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) {
      final threads = <ChatThread>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final participants = (data['participants'] as List? ?? const [])
            .whereType<String>()
            .toList();
        final otherId = participants.firstWhere(
          (p) => p != myUid,
          orElse: () => '',
        );
        if (otherId.isEmpty) continue;
        final names = data['names'] is Map ? data['names'] as Map : const {};
        final unread = data['unread'] is Map ? data['unread'] as Map : const {};
        final lastAt = data['lastMessageAt'];
        threads.add(ChatThread(
          chatId: doc.id,
          otherUserId: otherId,
          otherUserName: _nonEmpty(names[otherId]),
          lastMessage: (data['lastMessage'] ?? '').toString(),
          lastSenderId: (data['lastSenderId'] ?? '').toString(),
          lastMessageAt: lastAt is Timestamp ? lastAt.toDate().toLocal() : null,
          unreadForMe: _asCount(unread[myUid]),
          unreadForOther: _asCount(unread[otherId]),
        ));
      }
      return threads;
    });
  }

  /// Sum of my unread counters across all chats (for badges).
  Stream<int> totalUnreadStream(String myUid) => inboxStream(myUid)
      .map((threads) => threads.fold<int>(0, (s, t) => s + t.unreadForMe));

  static int _asCount(Object? v) {
    if (v is num) return v < 0 ? 0 : v.toInt();
    return 0;
  }

  static String? _nonEmpty(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
