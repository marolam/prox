import "package:cloud_firestore/cloud_firestore.dart";

class ChatMessageService {
  ChatMessageService._();
  static final ChatMessageService instance = ChatMessageService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _msgs(String chatId) =>
      _db.collection("chats").doc(chatId).collection("messages");

  Future<void> sendText({
    required String chatId,
    required String fromUid,
    required String toUid,
    required String text,
  }) async {
    final String t = text.trim();
    if (t.isEmpty) return;

    final now = FieldValue.serverTimestamp();

    await _msgs(chatId).add(<String, Object?>{
      "from": fromUid,
      "to": toUid,
      "text": t,
      "ts": now,
      "read": false,
      "readAt": null,
      "kind": "text",
    });

    // Best-effort thread metadata
    final String preview = (t.length > 120) ? "${t.substring(0, 120)}..." : t;

    await _db.collection("chats").doc(chatId).set(<String, Object?>{
      "lastMessage": preview,
      "lastMessageAt": now,
      "updatedAt": now,
    }, SetOptions(merge: true));
  }

  /// Mark latest unread messages addressed to me as read.
  ///
  /// IMPORTANT: We intentionally avoid orderBy(...) to reduce index friction in tester builds.
  Future<int> markThreadRead({
    required String chatId,
    required String myUid,
    int limit = 40,
  }) async {
    try {
      final qs = await _msgs(chatId)
          .where("to", isEqualTo: myUid)
          .where("read", isEqualTo: false)
          .limit(limit)
          .get();

      if (qs.docs.isEmpty) return 0;

      final batch = _db.batch();
      for (final d in qs.docs) {
        batch.set(d.reference, <String, Object?>{
          "read": true,
          "readAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      return qs.docs.length;
    } catch (_) {
      return 0;
    }
  }
}
