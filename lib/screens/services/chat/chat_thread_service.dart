import "package:cloud_firestore/cloud_firestore.dart";

class ChatThreadService {
  ChatThreadService._();
  static final ChatThreadService instance = ChatThreadService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String chatIdFor(String a, String b) {
    final pair = [a, b]..sort();
    return pair.join("_");
  }

  Future<String> ensureChat({
    required String myUid,
    required String otherUid,
  }) async {
    final id = chatIdFor(myUid, otherUid);
    final ref = _db.collection("chats").doc(id);

    // Critical: avoid transactions here. Transactions do an implicit read that
    // fails rules when the doc doesn't exist yet.
    await ref.set(<String, Object?>{
      "id": id,
      "participants": [myUid, otherUid],
      "updatedAt": FieldValue.serverTimestamp(),

      // Initialize gate on first write (safe merge if already present)
      "chatGate": <String, Object?>{
        "status": "requested",
        "requestedBy": myUid,
        "requestedAt": FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));

    return id;
  }
}
