import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/foundation.dart";
import "package:prox/services/chat/chat_request_policy.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/matching/matching_mode_service.dart";

class ChatGateStatus {
  final String status; // requested|accepted|declined|expired
  final String requestedBy;
  final Timestamp? requestedAt;
  final DateTime? requestDeadline;
  final bool requestExpiredLocally;
  final String acceptedBy;
  final Timestamp? acceptedAt;
  final bool canRenew;
  final String declinedBy;
  final Timestamp? declinedAt;

  const ChatGateStatus({
    required this.status,
    required this.requestedBy,
    this.requestedAt,
    this.requestDeadline,
    this.requestExpiredLocally = false,
    this.acceptedBy = "",
    this.acceptedAt,
    this.canRenew = false,
    this.declinedBy = "",
    this.declinedAt,
  });

  static ChatGateStatus fromChatDoc(Map<String, dynamic>? d) {
    final gate = (d?["chatGate"] is Map)
        ? Map<String, dynamic>.from(d?["chatGate"] as Map)
        : <String, dynamic>{};

    final status = (gate["status"] ?? "").toString().trim();
    final requestedBy = (gate["requestedBy"] ?? "").toString().trim();
    final normalizedStatus = status.isEmpty ? "requested" : status;
    final deadline = ChatRequestPolicy.deadline(gate);
    final requestExpiredLocally =
      normalizedStatus == "requested" &&
      (deadline == null || !deadline.isAfter(DateTime.now()));

    return ChatGateStatus(
      canRenew: ChatRequestPolicy.canRenew(d ?? {}),
      status: normalizedStatus,
      requestedBy: requestedBy,
      requestedAt: gate["requestedAt"] is Timestamp
          ? gate["requestedAt"] as Timestamp
          : null,
      requestDeadline: deadline,
      requestExpiredLocally: requestExpiredLocally,
      acceptedBy: (gate["acceptedBy"] ?? "").toString().trim(),
      acceptedAt: gate["acceptedAt"] is Timestamp
          ? gate["acceptedAt"] as Timestamp
          : null,
      declinedBy: (gate["declinedBy"] ?? "").toString().trim(),
      declinedAt: gate["declinedAt"] is Timestamp
          ? gate["declinedAt"] as Timestamp
          : null,
    );
  }

  bool get isAccepted => status == "accepted";
  bool get isDeclined => status == "declined";
  bool get isExpired => status == "expired";
  bool get isStaleOrExpired => isExpired || requestExpiredLocally;
}

class ChatGateService {
  ChatGateService._({
    FirebaseFirestore? firestore,
    String? Function()? uidProvider,
    bool Function()? activeProvider,
    void Function()? onPenalty,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _uidProvider =
           uidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _activeProvider =
           activeProvider ?? (() => MatchingModeService.instance.isActive),
       _onPenalty =
           onPenalty ??
           (() =>
               MatchingModeService.instance.registerActiveNoResponsePenalty());
  @visibleForTesting
  factory ChatGateService.forTesting({
    required FirebaseFirestore firestore,
    required String? Function() uidProvider,
    required bool Function() activeProvider,
    required void Function() onPenalty,
  }) => ChatGateService._(
    firestore: firestore,
    uidProvider: uidProvider,
    activeProvider: activeProvider,
    onPenalty: onPenalty,
  );
  static final ChatGateService instance = ChatGateService._();

  final FirebaseFirestore _db;
  final String? Function() _uidProvider;
  final bool Function() _activeProvider;
  final void Function() _onPenalty;

  static const Duration activeAcceptWindow = Duration(seconds: 60);
  static const Duration activeTimeoutPenaltyLock = Duration(minutes: 10);

  DateTime? _lastExpirySweepAt;
  String? _lastExpiryUid;

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
    final uid = (forUid ?? _uidProvider() ?? "").trim();
    if (uid.isEmpty) return const Stream<DateTime?>.empty();

    return _incomingRequestedChatsQuery(uid).snapshots().map((snap) {
      if (_uidProvider() != uid) return null;
      DateTime? soonest;
      for (final doc in snap.docs) {
        final d = doc.data();
        final gate = (d["chatGate"] is Map)
            ? Map<String, dynamic>.from(d["chatGate"] as Map)
            : <String, dynamic>{};

        final requestedBy = (gate["requestedBy"] ?? "").toString().trim();
        if (requestedBy.isEmpty || requestedBy == uid) continue;

        if (!ChatRequestPolicy.isActiveRequest(gate) || d['closedAt'] != null)
          continue;
        final due = ChatRequestPolicy.deadline(gate);
        if (due == null) continue;
        final existingSoonest = soonest;
        if (existingSoonest == null || due.isBefore(existingSoonest)) {
          soonest = due;
        }
      }
      return soonest;
    });
  }

  Future<void> enforceExpiredIncomingRequestsIfNeeded({String? forUid}) async {
    final uid = (forUid ?? _uidProvider() ?? "").trim();
    if (uid.isEmpty) return;

    final now = DateTime.now();
    if (_uidProvider() != uid) return;
    if (_lastExpiryUid == uid &&
        _lastExpirySweepAt != null &&
        now.difference(_lastExpirySweepAt!) <
            (_activeProvider()
                ? const Duration(seconds: 3)
                : const Duration(seconds: 45)))
      return;
    _lastExpiryUid = uid;
    _lastExpirySweepAt = now;
    final snap = await _incomingRequestedChatsQuery(uid).get();
    if (_uidProvider() != uid) return;
    var penalize = false;
    for (final doc in snap.docs) {
      final observed = doc.data();
      final observedGate = observed['chatGate'] is Map
          ? Map<String, dynamic>.from(observed['chatGate'] as Map)
          : <String, dynamic>{};
      final observedDue = ChatRequestPolicy.deadline(observedGate);
      if (observed['closedAt'] != null ||
          observedGate['requestedBy'] == uid ||
          observedDue == null ||
          now.isBefore(observedDue))
        continue;
      // Recheck in a transaction: a slow sweep must not overwrite acceptance
      // or a freshly renewed request on the other phone.
      final activeExpired = await _db.runTransaction((tx) async {
        if (_uidProvider() != uid) return false;
        final current = await tx.get(doc.reference);
        if (_uidProvider() != uid) return false;
        final d = current.data() ?? <String, dynamic>{};
        final gate = d['chatGate'] is Map
            ? Map<String, dynamic>.from(d['chatGate'] as Map)
            : <String, dynamic>{};
        final due = ChatRequestPolicy.deadline(gate);
        if (d['closedAt'] != null ||
            gate['status'] != 'requested' ||
            gate['requestedBy'] == uid ||
            gate['requestedBy'] == null ||
            due == null ||
            DateTime.now().isBefore(due))
          return false;
        tx.update(doc.reference, {
          'chatGate.status': 'expired',
          'chatGate.expiredAt': FieldValue.serverTimestamp(),
          'chatGate.expiredBySystem': true,
          'chatGate.expiredForUid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return ChatRequestPolicy.isActiveRequest(gate);
      });
      penalize = penalize || activeExpired;
    }
    if (_uidProvider() == uid && penalize && _activeProvider()) _onPenalty();
  }

  Future<void> enforceChatLifecycleForUid({String? forUid}) async {
    await enforceExpiredIncomingRequestsIfNeeded(forUid: forUid);
  }

  bool shouldSuppressIncomingCountdownForUid(String uid) {
    return _uidProvider() != uid || !_activeProvider();
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

  Future<void> accept({required String chatId, required String accepterUid}) =>
      _respond(chatId, accepterUid, accept: true);

  Future<void> decline({required String chatId, required String declinerUid}) =>
      _respond(chatId, declinerUid, accept: false);

  Future<void> _respond(
    String chatId,
    String uid, {
    required bool accept,
  }) async {
    if (_uidProvider() != uid) throw StateError('Sign in to respond.');
    final ref = _chat(chatId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final gate = data['chatGate'] is Map
          ? Map<String, dynamic>.from(data['chatGate'] as Map)
          : <String, dynamic>{};
      final due = ChatRequestPolicy.deadline(gate);
      if (_uidProvider() != uid ||
          data['closedAt'] != null ||
          gate['status'] != 'requested' ||
          gate['requestedBy'] == uid ||
          !(data['participants'] is List &&
              (data['participants'] as List).contains(uid)) ||
          (due != null && !DateTime.now().isBefore(due)))
        throw StateError('This request is no longer available.');
      tx.update(ref, {
        'chatGate.status': accept ? 'accepted' : 'declined',
        if (accept) 'chatGate.acceptedBy': uid else 'chatGate.declinedBy': uid,
        if (accept)
          'chatGate.acceptedAt': FieldValue.serverTimestamp()
        else
          'chatGate.declinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
