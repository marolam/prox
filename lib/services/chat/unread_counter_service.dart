import "package:cloud_firestore/cloud_firestore.dart";

class UnreadCounterService {
  UnreadCounterService._();
  static final UnreadCounterService instance = UnreadCounterService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<int> unreadCount(String chatId, String myUid) {
    return _db
        .collection("chats")
        .doc(chatId)
        .collection("messages")
        .where("to", isEqualTo: myUid)
        .where("read", isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Best-effort clear for tester builds (keeps unread counters sane).
  /// Avoids orderBy(...) to reduce index friction.
  Future<void> clearUnreadBestEffort(String chatId, String myUid) async {
    try {
      final qs = await _db
          .collection("chats")
          .doc(chatId)
          .collection("messages")
          .where("to", isEqualTo: myUid)
          .where("read", isEqualTo: false)
          .limit(40)
          .get();

      if (qs.docs.isEmpty) return;

      final batch = _db.batch();
      for (final d in qs.docs) {
        batch.set(d.reference, <String, Object?>{
          "read": true,
          "readAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {}
  }
}
