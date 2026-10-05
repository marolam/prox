import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/services/chat/chat_request_policy.dart";

class ChatThreadService {
  ChatThreadService._({
    FirebaseFirestore? firestore,
    String? Function()? uidProvider,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _uidProvider =
           uidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid);
  static final ChatThreadService instance = ChatThreadService._();

  @visibleForTesting
  factory ChatThreadService.forTesting({
    required FirebaseFirestore firestore,
    required String? Function() uidProvider,
  }) => ChatThreadService._(firestore: firestore, uidProvider: uidProvider);

  final FirebaseFirestore _db;
  final String? Function() _uidProvider;

  String chatIdFor(String a, String b) {
    final pair = [a, b]..sort();
    return pair.join("_");
  }

  Future<String> ensureChat({
    required String myUid,
    required String otherUid,
    bool renewExpired = false,
    MatchingModeKind? modeKind,
  }) async {
    if (myUid.isEmpty ||
        otherUid.isEmpty ||
        myUid.contains('/') ||
        otherUid.contains('/') ||
        myUid != myUid.trim() ||
        otherUid != otherUid.trim() ||
        myUid == otherUid) {
      throw ArgumentError('A chat requires two valid, different users.');
    }
    void checkSession() {
      if (_uidProvider() != myUid)
        throw StateError('The signed-in account changed.');
    }

    checkSession();
    final requestMode =
        modeKind ??
        UserSettingsService.instance.current.matchDiscovery.modeKind;
    final id = chatIdFor(myUid, otherUid);
    final ref = _db.collection("chats").doc(id);

    // Rules allow an authenticated read of a missing chat for this preflight.
    // Only the winning creator initializes it. Opening from the other side
    // must not reorder participants, replace consent or restart a closed chat.
    await _db.runTransaction((tx) async {
      checkSession();
      final snapshot = await tx.get(ref);
      checkSession();
      if (snapshot.exists) {
        final participants = snapshot.data()?['participants'];
        if (participants is! List ||
            participants.length != 2 ||
            !participants.contains(myUid) ||
            !participants.contains(otherUid)) {
          throw StateError('This chat does not belong to this pair.');
        }
        if (!renewExpired || !ChatRequestPolicy.canRenew(snapshot.data()!))
          return;
      }
      final recipient = await tx.get(
        _db.doc('users/$otherUid/presence/current'),
      );
      checkSession();
      final window = ChatRequestPolicy.creationWindow(
        requestMode,
        recipient.data() ?? {},
        DateTime.now(),
      );
      final gate = <String, Object?>{
        'status': 'requested',
        'requestedBy': myUid,
        'requestedAt': FieldValue.serverTimestamp(),
        'modeKind': requestMode.name,
        'responseWindowSeconds': window.inSeconds,
      };
      if (snapshot.exists) {
        // Explicit renewal replaces timeout metadata but preserves the chat.
        tx.update(ref, {
          for (final entry in gate.entries)
            'chatGate.${entry.key}': entry.value,
          'chatGate.expiredAt': FieldValue.delete(),
          'chatGate.expiredBySystem': FieldValue.delete(),
          'chatGate.expiredForUid': FieldValue.delete(),
          'chatGate.rolledBackByPolicy': FieldValue.delete(),
          'chatGate.rolledBackAt': FieldValue.delete(),
          'chatGate.rollbackReason': FieldValue.delete(),
          'chatGatePolicy': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      tx.set(ref, <String, Object?>{
        "id": id,
        "participants": [myUid, otherUid]..sort(),
        "updatedAt": FieldValue.serverTimestamp(),
        "chatGate": gate,
      });
    }, timeout: const Duration(seconds: 8));
    checkSession();
    return id;
  }
}
