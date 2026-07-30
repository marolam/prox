import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/matching/matching_mode_service.dart";

class ChatGateStatus {
  final String status; // requested|accepted|declined|expired
  final String requestedBy;
  final Timestamp? requestedAt;
  final String acceptedBy;
  final Timestamp? acceptedAt;
  final String declinedBy;
  final Timestamp? declinedAt;

  const ChatGateStatus({
    required this.status,
    required this.requestedBy,
    this.requestedAt,
    this.acceptedBy = "",
    this.acceptedAt,
    this.declinedBy = "",
    this.declinedAt,
  });

  static ChatGateStatus fromChatDoc(Map<String, dynamic>? d) {
    final gate = (d?["chatGate"] is Map)
        ? Map<String, dynamic>.from(d?["chatGate"] as Map)
        : <String, dynamic>{};

    final status = (gate["status"] ?? "").toString().trim();
    final requestedBy = (gate["requestedBy"] ?? "").toString().trim();

    return ChatGateStatus(
      status: status.isEmpty ? "requested" : status,
      requestedBy: requestedBy,
      requestedAt: gate["requestedAt"] is Timestamp ? gate["requestedAt"] as Timestamp : null,
      acceptedBy: (gate["acceptedBy"] ?? "").toString().trim(),
      acceptedAt: gate["acceptedAt"] is Timestamp ? gate["acceptedAt"] as Timestamp : null,
      declinedBy: (gate["declinedBy"] ?? "").toString().trim(),
      declinedAt: gate["declinedAt"] is Timestamp ? gate["declinedAt"] as Timestamp : null,
    );
  }

  bool get isAccepted => status == "accepted";
  bool get isDeclined => status == "declined";
  bool get isExpired => status == "expired";
}

class ChatGateService {
  ChatGateService._();
  static final ChatGateService instance = ChatGateService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const Duration activeAcceptWindow = Duration(seconds: 60);
  static const Duration activeTimeoutPenaltyLock = Duration(minutes: 10);

  DateTime? _lastExpirySweepAt;

  DocumentReference<Map<String, dynamic>> _chat(String chatId) =>
      _db.collection("chats").doc(chatId);

  Query<Map<String, dynamic>> _incomingRequestedChatsQuery(String uid) {
    return _db
        .collection("chats")
        .where("participants", arrayContains: uid)
        .where("chatGate.status", isEqualTo: "requested")
        .limit(50);
  }

  Stream<DateTime?> watchIncomingRequestDeadline({String? forUid}) {
    final uid = (forUid ?? _auth.currentUser?.uid ?? "").trim();
    if (uid.isEmpty) return const Stream<DateTime?>.empty();

    return _incomingRequestedChatsQuery(uid).snapshots().map((snap) {
      DateTime? soonest;
      for (final doc in snap.docs) {
        final d = doc.data();
        final gate = (d["chatGate"] is Map)
            ? Map<String, dynamic>.from(d["chatGate"] as Map)
            : <String, dynamic>{};

        final requestedBy = (gate["requestedBy"] ?? "").toString().trim();
        if (requestedBy.isEmpty || requestedBy == uid) continue;

        final ts = gate["requestedAt"];
        if (ts is! Timestamp) continue;

        final due = ts.toDate().add(activeAcceptWindow);
        final existingSoonest = soonest;
        if (existingSoonest == null || due.isBefore(existingSoonest)) {
          soonest = due;
        }
      }
      return soonest;
    });
  }

  Future<void> enforceExpiredIncomingRequestsIfNeeded({String? forUid}) async {
    final uid = (forUid ?? _auth.currentUser?.uid ?? "").trim();
    if (uid.isEmpty) return;

    final now = DateTime.now();
    if (_lastExpirySweepAt != null && now.difference(_lastExpirySweepAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastExpirySweepAt = now;

    final snap = await _incomingRequestedChatsQuery(uid).get();
    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    bool expiredIncoming = false;

    for (final doc in snap.docs) {
      final d = doc.data();
      final gate = (d["chatGate"] is Map)
          ? Map<String, dynamic>.from(d["chatGate"] as Map)
          : <String, dynamic>{};

      final requestedBy = (gate["requestedBy"] ?? "").toString().trim();
      if (requestedBy.isEmpty || requestedBy == uid) continue;

      final ts = gate["requestedAt"];
      if (ts is! Timestamp) continue;

      final due = ts.toDate().add(activeAcceptWindow);
      if (now.isBefore(due)) continue;

      expiredIncoming = true;
      batch.set(doc.reference, <String, Object?>{
        "chatGate": <String, Object?>{
          "status": "expired",
          "expiredAt": FieldValue.serverTimestamp(),
          "expiredBySystem": true,
          "expiredForUid": uid,
        },
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (!expiredIncoming) return;

    await batch.commit();

    final mode = MatchingModeService.instance;
    if (mode.isActive) {
      mode.registerActiveNoResponsePenalty();
    }
  }

  Future<void> ensureRequested({
    required String chatId,
    required String requestedBy,
  }) async {
    final ref = _chat(chatId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final d = snap.data() ?? <String, dynamic>{};
      final gate = (d["chatGate"] is Map)
          ? Map<String, dynamic>.from(d["chatGate"] as Map)
          : <String, dynamic>{};

      final status = (gate["status"] ?? "").toString().trim();
      if (status.isNotEmpty) return;

      tx.set(ref, <String, Object?>{
        "chatGate": <String, Object?>{
          "status": "requested",
          "requestedBy": requestedBy,
          "requestedAt": FieldValue.serverTimestamp(),
        },
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> accept({required String chatId, required String accepterUid}) async {
    final ref = _chat(chatId);
    await ref.set(<String, Object?>{
      "chatGate": <String, Object?>{
        "status": "accepted",
        "acceptedBy": accepterUid,
        "acceptedAt": FieldValue.serverTimestamp(),
      },
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> decline({required String chatId, required String declinerUid}) async {
    final ref = _chat(chatId);
    await ref.set(<String, Object?>{
      "chatGate": <String, Object?>{
        "status": "declined",
        "declinedBy": declinerUid,
        "declinedAt": FieldValue.serverTimestamp(),
      },
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
