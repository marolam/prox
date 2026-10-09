import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "dart:async";

import "package:prox/services/party_connection_service.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/utils/auth_bound_stream.dart";
import "package:prox/services/auth/authenticated_callable.dart";

class PartyMemberEntry {
  final String otherUid;
  final DateTime? since;
  final bool mutual;
  final String source;
  bool get isMentorContact => source == "referralMentor" && !mutual;

  const PartyMemberEntry({
    required this.otherUid,
    required this.since,
    required this.mutual,
    required this.source,
  });

  static DateTime? _parseSince(Map<String, dynamic> d) {
    final v = d["since"];
    if (v is Timestamp) return v.toDate();

    final ms = d["sinceClientMs"];
    if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    final ms2 = int.tryParse((ms ?? "").toString());
    if (ms2 != null) return DateTime.fromMillisecondsSinceEpoch(ms2);

    return null;
  }

  static PartyMemberEntry fromDoc(String otherUid, Map<String, dynamic> d) {
    return PartyMemberEntry(
      otherUid: otherUid,
      since: _parseSince(d),
      mutual: d["mutual"] == true && d["metInPerson"] == true,
      source: (d["source"] ?? "").toString(),
    );
  }
}

class PartyAddRequest {
  final String docId;
  final String fromUid;
  final String toUid;
  final String status;
  final DateTime? requestedAt;
  final DateTime? updatedAt;

  const PartyAddRequest({
    required this.docId,
    required this.fromUid,
    required this.toUid,
    required this.status,
    required this.requestedAt,
    required this.updatedAt,
  });

  bool get isRequested => status == "requested";

  static DateTime? _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) {
      final asInt = int.tryParse(v);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(v);
    }
    return null;
  }

  static PartyAddRequest fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final requested =
        _parseDate(d["requestedAt"]) ?? _parseDate(d["requestedAtClientMs"]);
    final updated = _parseDate(d["updatedAt"]);
    return PartyAddRequest(
      docId: doc.id,
      fromUid: (d["fromUid"] ?? "").toString().trim(),
      toUid: (d["toUid"] ?? "").toString().trim(),
      status: (d["status"] ?? "requested").toString().trim().toLowerCase(),
      requestedAt: requested,
      updatedAt: updated,
    );
  }
}

class PartyService {
  PartyService._();
  static final PartyService instance = PartyService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const Duration _presenceFreshness = Duration(minutes: 5);

  static bool isOnlinePresenceData(
    Map<String, dynamic>? data, {
    DateTime? now,
  }) {
    if (data == null) return false;
    final ts = data["ts"];
    final expiresAt = data["expiresAt"];
    if (ts is! Timestamp || expiresAt is! Timestamp) return false;
    final current = now ?? DateTime.now();
    return expiresAt.toDate().isAfter(current) &&
        current.difference(ts.toDate()) <= _presenceFreshness;
  }

  CollectionReference<Map<String, dynamic>> _party(String uid) =>
      _db.collection("users").doc(uid).collection("party");

  DocumentReference<Map<String, dynamic>> _partyNetworkSettings(String uid) =>
      _db
          .collection("users")
          .doc(uid)
          .collection("settings")
          .doc("partyNetwork");

  DocumentReference<Map<String, dynamic>> _partyNetworkRequest(String uid) =>
      _db.collection("partyNetworkRequests").doc(uid);

  bool _isPartyMemberDocId(String docId) {
    final id = docId.trim();
    if (id.isEmpty) return false;
    // Reserved metadata docs that are not user UIDs.
    if (id == "current" || id == "partySettings") return false;
    return true;
  }

  /// Codes and in-person evidence are checked on the server. No client Party writes.
  Future<String> startInPersonDirectInviteSession({
    Duration ttl = const Duration(minutes: 3),
    String? expectedUid,
  }) async {
    final uid = _me();
    if (expectedUid != null && expectedUid != uid)
      throw StateError('Your signed-in account changed. Reopen Party.');
    await PresenceWriter.instance.writeOneShot(reason: "party_in_person_start");
    if (_me() != uid)
      throw StateError('Your signed-in account changed. Reopen Party.');
    final data = await PartyConnectionService.instance.inPersonCall(
      'startPartyInPersonSession',
      expectedUid: uid,
    );
    return data['code'] as String;
  }

  Future<void> stopInPersonDirectInviteSession({String? expectedUid}) async {
    await PartyConnectionService.instance.inPersonCall(
      'stopPartyInPersonSession',
      expectedUid: expectedUid,
    );
  }

  Future<InPersonDirectInviteResult> confirmInPersonDirectInviteCode(
    String rawCode, {
    String? expectedUid,
  }) async {
    final uid = _me();
    if (expectedUid != null && expectedUid != uid)
      throw StateError('Your signed-in account changed. Reopen Party.');
    await PresenceWriter.instance.writeOneShot(
      reason: "party_in_person_confirm",
    );
    if (_me() != uid)
      throw StateError('Your signed-in account changed. Reopen Party.');
    final data = await PartyConnectionService.instance.inPersonCall(
      'confirmPartyInPersonCode',
      expectedUid: uid,
      data: {'code': rawCode},
    );
    final paired = data['status'] == 'connected';
    return InPersonDirectInviteResult(
      ok: true,
      paired: paired,
      peerUid: data['peerUid'] as String?,
      message: paired
          ? "You met in person and both agreed. You are now in each other's Party."
          : "Your agreement is saved. Ask them to enter your code to finish.",
    );
  }

  Future<void> syncReferralInPersonAutoJoins() async {
    await callAuthenticatedFunction<Map<String, dynamic>>(
      'refreshReferralMentor',
      {'expectedUid': _me()},
    );
  }

  Future<void> requestPartyAdd(String otherUid) =>
      PartyConnectionService.instance.act(otherUid.trim(), 'add');

  Stream<List<PartyAddRequest>> _watchPartyRequests({required bool incoming}) =>
      authBoundStream<List<PartyAddRequest>>(
        accountChanges: _auth.authStateChanges().map((u) => u?.uid),
        currentUid: () => _auth.currentUser?.uid,
        empty: const <PartyAddRequest>[],
        watch: (uid) => PartyConnectionService.instance
            .watchPending(uid)
            .map(
              (pending) => pending
                  .where(
                    (p) =>
                        p.isActive(DateTime.now()) &&
                        (incoming
                            ? p.theirDecision == 'add'
                            : p.myDecision == 'add'),
                  )
                  .map(
                    (p) => PartyAddRequest(
                      docId: p.otherUid,
                      fromUid: incoming ? p.otherUid : uid,
                      toUid: incoming ? uid : p.otherUid,
                      status: 'requested',
                      requestedAt: null,
                      updatedAt: null,
                    ),
                  )
                  .toList(growable: false),
            ),
      );

  Stream<List<PartyAddRequest>> watchIncomingPartyAddRequests() =>
      _watchPartyRequests(incoming: true);

  Stream<List<PartyAddRequest>> watchOutgoingPartyAddRequests() =>
      _watchPartyRequests(incoming: false);

  Future<void> acceptPartyAddRequestFrom(String requesterUid) =>
      PartyConnectionService.instance.act(requesterUid.trim(), 'add');

  Future<void> declinePartyAddRequestFrom(String requesterUid) =>
      PartyConnectionService.instance.act(requesterUid.trim(), 'later');

  String _me() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError("Not signed in");
    }
    return uid;
  }

  Future<bool> isInMyParty(String otherUid) async {
    final uid = _me();
    final other = otherUid.trim();
    if (other.isEmpty) return false;
    final snap = await _party(uid).doc(other).get();
    return snap.data()?["mutual"] == true &&
        snap.data()?["metInPerson"] == true;
  }

  Stream<Set<String>> watchOnlinePartyUids(Iterable<String> partyUids) {
    final uids = partyUids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet();
    if (uids.isEmpty) return Stream<Set<String>>.value(const <String>{});

    final presence = <String, Map<String, dynamic>?>{};
    final subscriptions = <StreamSubscription>[];
    Timer? timer;
    late final StreamController<Set<String>> controller;

    Set<String> onlineNow() {
      final now = DateTime.now();
      return presence.entries
          .where((entry) {
            return isOnlinePresenceData(entry.value, now: now);
          })
          .map((entry) => entry.key)
          .toSet();
    }

    void emit() {
      if (!controller.isClosed) controller.add(onlineNow());
    }

    controller = StreamController<Set<String>>(
      onListen: () {
        for (final uid in uids) {
          subscriptions.add(
            _db
                .collection("users")
                .doc(uid)
                .collection("presence")
                .doc("current")
                .snapshots()
                .listen(
                  (snap) {
                    presence[uid] = snap.data();
                    emit();
                  },
                  onError: (_) {
                    presence[uid] = null;
                    emit();
                  },
                ),
          );
        }
        timer = Timer.periodic(const Duration(seconds: 30), (_) => emit());
        emit();
      },
      onCancel: () async {
        timer?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Live stream for "is other in my party?"
  Stream<bool> watchIsInMyParty(String otherUid) {
    final uid = _me();
    final other = otherUid.trim();
    if (other.isEmpty) return const Stream<bool>.empty();
    return _party(uid)
        .doc(other)
        .snapshots()
        .map(
          (s) =>
              s.data()?["mutual"] == true && s.data()?["metInPerson"] == true,
        );
  }

  /// Canonical Party list stream: reads /users/{uid}/party/*
  Stream<List<PartyMemberEntry>> watchMyPartyEntries({
    bool includeMentorContacts = false,
  }) {
    return authBoundStream<List<PartyMemberEntry>>(
      accountChanges: _auth.authStateChanges().map((user) => user?.uid),
      currentUid: () => _auth.currentUser?.uid,
      empty: const <PartyMemberEntry>[],
      watch: (uid) => _party(uid).snapshots().map((qs) {
        final out = <PartyMemberEntry>[];
        for (final doc in qs.docs) {
          if (!_isPartyMemberDocId(doc.id)) continue;
          if (doc.data()["mutual"] != true ||
              (doc.data()["metInPerson"] != true &&
                  !(includeMentorContacts &&
                      doc.data()["source"] == "referralMentor")))
            continue;
          final other = doc.id.trim();
          out.add(PartyMemberEntry.fromDoc(other, doc.data()));
        }

        // Sort: newest since oldest; fallback to uid.
        out.sort((a, b) {
          final ad = a.since;
          final bd = b.since;
          if (ad == null && bd == null) return a.otherUid.compareTo(b.otherUid);
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });

        return out;
      }),
    );
  }

  Stream<bool> watchPartyNetworkSharing() {
    final uid = _me();
    return _partyNetworkSettings(
      uid,
    ).snapshots().map((snap) => snap.data()?["sharingEnabled"] == true);
  }

  Future<void> setPartyNetworkSharing(bool enabled) async {
    final uid = _me();
    await _partyNetworkSettings(uid).set(<String, Object?>{
      "sharingEnabled": enabled,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<Map<String, dynamic>> watchPartyNetworkInsights() {
    final uid = _me();
    return _partyNetworkRequest(
      uid,
    ).snapshots().map((snap) => snap.data() ?? const <String, dynamic>{});
  }

  Future<void> refreshPartyNetworkInsights() async {
    final uid = _me();
    await _partyNetworkRequest(uid).set(<String, Object?>{
      "ownerUid": uid,
      "requestNonce": "${uid}_${DateTime.now().millisecondsSinceEpoch}",
      "requestedAt": FieldValue.serverTimestamp(),
      "status": "requested",
    }, SetOptions(merge: true));
  }

  /// Only a pending request backed by a completed meetup may be accepted here.
  Future<void> addToParty(String otherUid, {String source = "postMeetup"}) =>
      PartyConnectionService.instance.act(otherUid.trim(), 'add');

  /// Membership projections are reconciled by their server receipt.
  Future<void> reconcileMutual(String otherUid) async {}

  Stream<bool> watchMutual(String otherUid) {
    final uid = _me();
    final other = otherUid.trim();
    if (other.isEmpty) return const Stream<bool>.empty();

    return _party(uid).doc(other).snapshots().map((s) {
      final d = s.data();
      return d != null && d["mutual"] == true && d["metInPerson"] == true;
    });
  }

  Future<void> removeFromParty(String otherUid) async {
    await PartyConnectionService.instance.act(otherUid.trim(), 'remove');
  }
}

class InPersonDirectInviteResult {
  final bool ok;
  final bool paired;
  final String message;
  final String? peerUid;
  final InPersonProximityCheck? proximity;

  const InPersonDirectInviteResult({
    required this.ok,
    required this.paired,
    required this.message,
    this.peerUid,
    this.proximity,
  });
}

class InPersonProximityCheck {
  final bool ok;
  final String message;
  final double? distanceMeters;
  final int? mePresenceAgeSec;
  final int? peerPresenceAgeSec;

  const InPersonProximityCheck({
    required this.ok,
    required this.message,
    this.distanceMeters,
    this.mePresenceAgeSec,
    this.peerPresenceAgeSec,
  });
}
