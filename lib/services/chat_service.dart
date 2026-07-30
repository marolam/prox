import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _msgs(String chatId) =>
      _db.collection("chats").doc(chatId).collection("messages");

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String chatId) {
    return _msgs(chatId).orderBy("ts", descending: false).snapshots();
  }

  Future<String> ensureDirectChat(String otherUid) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    final other = otherUid.trim();
    if (me.isEmpty || other.isEmpty) {
      throw StateError("Sign in required to open chat.");
    }

    final ids = <String>[me, other]..sort();
    final chatId = "${ids[0]}__${ids[1]}";
    await _db.collection("chats").doc(chatId).set(<String, Object?>{
      "participants": ids,
      "isGroup": false,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return chatId;
  }

  Future<void> sendMessage({
    required String chatId,
    required String text,
    required String otherUid,
  }) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    final clean = text.trim();
    if (clean.isEmpty || me.isEmpty) return;

    await _msgs(chatId).add(<String, Object?>{
      "from": me,
      "to": otherUid,
      "text": clean,
      "kind": "text",
      "read": false,
      "ts": FieldValue.serverTimestamp(),
    });

    await _db.collection("chats").doc(chatId).set(<String, Object?>{
      "lastMessage": clean,
      "lastMessageAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendImageMessage({
    required String chatId,
    required String imageUrl,
    required String caption,
    required String otherUid,
  }) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (me.isEmpty) return;

    await _msgs(chatId).add(<String, Object?>{
      "from": me,
      "to": otherUid,
      "text": caption,
      "imageUrl": imageUrl,
      "kind": "image",
      "read": false,
      "ts": FieldValue.serverTimestamp(),
    });

    await _db.collection("chats").doc(chatId).set(<String, Object?>{
      "lastMessage": caption.trim().isEmpty ? "[image]" : caption.trim(),
      "lastMessageAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> createModeratedGroupChat({
    required List<String> memberUids,
    String? title,
  }) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    final members = <String>{
      ...memberUids.map((e) => e.trim()).where((e) => e.isNotEmpty)
    };
    if (me.isNotEmpty) members.add(me);

    final doc = await _db.collection("chats").add(<String, Object?>{
      "title": (title ?? "").trim(),
      "participants": members.toList(growable: false),
      "moderatorUid": me,
      "isGroup": true,
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> addMembersToModeratedGroupChat({
    required String chatId,
    required Iterable<String> memberUids,
  }) async {
    final incoming =
        memberUids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (incoming.isEmpty) return;

    final ref = _db.collection("chats").doc(chatId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final current = ((data["participants"] as List?) ?? const <dynamic>[])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      current.addAll(incoming);
      tx.set(
          ref,
          <String, Object?>{
            "participants": current.toList(growable: false),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  Future<void> removeMembersFromModeratedGroupChat({
    required String chatId,
    required Iterable<String> memberUids,
  }) async {
    final remove =
        memberUids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (remove.isEmpty) return;

    final ref = _db.collection("chats").doc(chatId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final current = ((data["participants"] as List?) ?? const <dynamic>[])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      current.removeAll(remove);
      tx.set(
          ref,
          <String, Object?>{
            "participants": current.toList(growable: false),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }
}
