import "dart:async";
import "dart:math";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:geolocator/geolocator.dart";

import "package:prox/models/presence_receipt.dart";
import "package:prox/services/offline/offline_outbox_service.dart";
import "package:prox/services/party_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/presence_receipt_service.dart";
import "package:prox/services/push_notifications.dart";
import "package:prox/services/ratings_service.dart";
import "package:prox/services/referral/referral_attribution.dart";
import "package:prox/services/referral_progress_updater.dart";
import "package:prox/services/reciprocity/reciprocity_service.dart";
import "package:prox/services/ttl/ttl_policy.dart";

enum ConfirmArrivalStatus {
  ok,
  notSignedIn,
  notFound,
  notParticipant,
  expired,
  completed,
  tooSoon,
  tooLate,
  failed,
}

class ConfirmArrivalResult {
  final ConfirmArrivalStatus status;
  final String message;
  final bool bothArrived;
  final bool wroteArrival;

  const ConfirmArrivalResult({
    required this.status,
    required this.message,
    this.bothArrived = false,
    this.wroteArrival = false,
  });

  bool get isOk => status == ConfirmArrivalStatus.ok;

  static const ConfirmArrivalResult notSignedIn = ConfirmArrivalResult(
    status: ConfirmArrivalStatus.notSignedIn,
    message: "You need to sign in first.",
  );
}

/// Tiny banner state for request/accept/decline/expire.
class MeetupRequestState {
  final String status;
  final String requestedBy;
  final Timestamp? requestedAt;
  final Timestamp? expiresAt;

  // Optional timestamps for richer UI (read-only; no schema migration required)
  final Timestamp? acceptedAt;
  final Timestamp? declinedAt;

  const MeetupRequestState({
    required this.status,
    required this.requestedBy,
    this.requestedAt,
    this.expiresAt,
    this.acceptedAt,
    this.declinedAt,
  });

  static MeetupRequestState? fromDoc(Map<String, dynamic>? d) {
    if (d == null) return null;
    final status = (d["status"] ?? "").toString().trim();
    if (status.isEmpty) return null;

    Timestamp? _ts(dynamic v) => v is Timestamp ? v : null;

    return MeetupRequestState(
      status: status,
      requestedBy: (d["requestedBy"] ?? "").toString().trim(),
      requestedAt: _ts(d["requestedAt"]),
      expiresAt: _ts(d["expiresAt"]),
      acceptedAt: _ts(d["acceptedAt"]),
      declinedAt: _ts(d["declinedAt"]),
    );
  }
}

class MeetupService {
  MeetupService._();
  static final MeetupService instance = MeetupService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const Duration requestWindow = Duration(minutes: 5);
  static const int expireMinutes = 15;

  static const Duration arrivalWindow = Duration(hours: 2);
  static const Duration minConfirmAfterCreate = Duration(seconds: 20);

  static const Duration tapVerifyWindow = Duration(seconds: 12);

  /// Rating window TTL (meetups/{id}.ratingExpiresAt)
  static const Duration ratingWindow = Duration(hours: 24);

  /// Privacy-first arrival radius (GPS proximity)
  static const double arrivalRadiusMeters = 150.0;

  /// UI cooldown after a decline before allowing a fresh request again.
  /// (No schema changes; just uses declinedAt if present.)
  static const Duration declineCooldown = Duration(minutes: 10);

  DocumentReference<Map<String, dynamic>> meetupRef(String meetupId) =>
      _db.collection("meetups").doc(meetupId);

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String meetupId) =>
      meetupRef(meetupId).snapshots();

  Future<void> exitAndFlushDashboards({
    required String chatId,
    required String otherUid,
    required String reason,
  }) async {
    final cleanChatId = chatId.trim();
    if (cleanChatId.isEmpty) return;

    await meetupRef(cleanChatId).set(<String, Object?>{
      "status": "expired",
      "exitReason": reason,
      if (otherUid.trim().isNotEmpty) "exitOtherUid": otherUid.trim(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMeetup(String meetupId) =>
      meetupRef(meetupId).snapshots();

  Stream<MeetupRequestState?> watchRequestState({required String chatId}) {
    return meetupRef(chatId)
        .snapshots()
        .map((snap) => MeetupRequestState.fromDoc(snap.data()));
  }

  bool _isExpiredByExpiresAt(Map<String, dynamic> d) {
    final exp = d["expiresAt"];
    if (exp is Timestamp) return TTLPolicy.isExpiredTs(exp);
    return false;
  }

  bool _hasLocation(Map<String, dynamic> d) {
    final lat = d["lat"];
    final lng = d["lng"];
    return (lat is num) && (lng is num);
  }

  Future<void> _writeMeetupRecapIfMissing({
    required String chatId,
    required String aUid,
    required String bUid,
    required Map<String, dynamic> meetupDoc,
  }) async {
    final id = chatId.trim();
    if (id.isEmpty) return;

    try {
      final chatRef = _db.collection("chats").doc(id);
      final chatSnap = await chatRef.get();
      final chatData = chatSnap.data() ?? <String, dynamic>{};
      if (chatData["meetupRecap"] is Map<String, dynamic>) {
        return;
      }

      final completedAt = meetupDoc["completedAt"];
      final lat = meetupDoc["lat"];
      final lng = meetupDoc["lng"];
      final matchedKeywords = meetupDoc["matchedKeywords"];

      await chatRef.set(<String, Object?>{
        "meetupRecap": <String, Object?>{
          "createdAt": FieldValue.serverTimestamp(),
          "completedAt": completedAt is Timestamp ? completedAt : FieldValue.serverTimestamp(),
          "lat": lat is num ? lat.toDouble() : null,
          "lng": lng is num ? lng.toDouble() : null,
          "aUid": aUid,
          "bUid": bUid,
          if (matchedKeywords != null) "matchedKeywords": matchedKeywords,
        },
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort safety write; do not block meetup completion flow.
    }
  }

  // -----------------------------
  // Decline cooldown helpers (UI-only logic, no schema changes)
  // -----------------------------
  Duration? declineCooldownLeftFromState(MeetupRequestState? s) {
    if (s == null) return null;
    if (s.status != "declined") return null;
    final ts = s.declinedAt;
    if (ts == null) return null;

    final until = ts.toDate().add(declineCooldown);
    final left = until.difference(DateTime.now());
    return left > Duration.zero ? left : Duration.zero;
  }

  Future<Duration?> declineCooldownLeft(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return null;
    try {
      final snap = await meetupRef(id).get();
      final d = snap.data();
      if (d == null) return null;
      final s = MeetupRequestState.fromDoc(d);
      return declineCooldownLeftFromState(s);
    } catch (_) {
      return null;
    }
  }

  // -----------------------------
  // Rating window hardening
  // -----------------------------
  bool _isRatingWindowOpenFromDoc(Map<String, dynamic> d) {
    final exp = d["ratingExpiresAt"];
    if (exp is! Timestamp) return false;
    return exp.toDate().isAfter(DateTime.now());
  }

  /// Ensures ratingStartedAt + ratingExpiresAt exist and are open for completed meetups.
  /// This is a safety valve so stale/expired windows never block ratings UI.
  Future<void> ensureRatingWindowOpen(String meetupId) async {
    final id = meetupId.trim();
    if (id.isEmpty) return;

    final ref = meetupRef(id);

    try {
      final snap = await ref.get();
      if (!snap.exists) return;

      final d = snap.data() ?? <String, dynamic>{};
      final status = (d["status"] ?? "").toString().trim();
      if (status != "completed") return;

      if (_isRatingWindowOpenFromDoc(d)) return;

      final completedAt = d["completedAt"];
      final DateTime base =
          (completedAt is Timestamp) ? completedAt.toDate() : DateTime.now();

      await ref.set(<String, Object?>{
        "ratingStartedAt": (completedAt is Timestamp) ? completedAt : FieldValue.serverTimestamp(),
        "ratingExpiresAt": Timestamp.fromDate(base.add(ratingWindow)),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // -----------------------------
  // Arrival code (fallback path)
  // -----------------------------
  String arrivalCodeNow(String meetupId) {
    final String id = meetupId.trim();
    if (id.isEmpty) return "0000";

    final int window = (DateTime.now().millisecondsSinceEpoch / 30000).floor();
    final int seed = id.codeUnits.fold<int>(0, (a, b) => a + b) ^ window;

    final int code = (seed.abs() * 1103515245 + 12345) & 0x7fffffff;
    return (code % 10000).toString().padLeft(4, "0");
  }

  bool arrivalCodeValid(String meetupId, String code) {
    final c = code.trim();
    if (c.length != 4) return false;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final delta in <int>[-1, 0, 1]) {
      final int window = (nowMs / 30000).floor() + delta;
      final int seed =
          meetupId.trim().codeUnits.fold<int>(0, (a, b) => a + b) ^ window;
      final int v =
          ((seed.abs() * 1103515245 + 12345) & 0x7fffffff) % 10000;
      if (v.toString().padLeft(4, "0") == c) return true;
    }
    return false;
  }

  // -----------------------------
  // Meetup request flow
  // -----------------------------
  Future<void> requestMeetup({
    required String chatId,
    required String otherUid,
  }) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError("Not signed in");
    if (chatId.trim().isEmpty) throw StateError("Missing chatId");

    final ref = meetupRef(chatId);

    await ref.set(<String, Object?>{
      "id": chatId,
      "chatId": chatId,
      "status": "requested",
      "requestedBy": me.uid,
      "requestedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
      "aUid": me.uid,
      "bUid": otherUid,
      "plannerUid": me.uid,
      "locationStatus": "none",
      "expiresAt": TTLPolicy.expiresAtFromNow(requestWindow),

      // Clear any prior decision timestamps so UI doesn't get stuck.
      "acceptedAt": FieldValue.delete(),
      "acceptedBy": FieldValue.delete(),
      "declinedAt": FieldValue.delete(),
      "declinedBy": FieldValue.delete(),
    }, SetOptions(merge: true));

    // Best effort: normalize expiresAt from server timestamp.
    try {
      final snap = await ref.get();
      final d = snap.data() ?? <String, dynamic>{};
      final ts = d["requestedAt"];
      if (ts is Timestamp) {
        await ref.set(<String, Object?>{
          "expiresAt": Timestamp.fromDate(ts.toDate().add(requestWindow)),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}

    unawaited(PushNotifications.instance.notifyMeetupEvent(
      chatId: chatId,
      creatorUid: me.uid,
      otherUid: otherUid,
      status: "requested",
    ));
  }

  Future<void> acceptMeetupRequest({
    required String chatId,
    String? otherUid,
  }) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError("Not signed in");
    final ref = meetupRef(chatId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError("not_found");
      final d = snap.data() ?? <String, dynamic>{};

      final status = (d["status"] ?? "").toString();
      if (status != "requested") return;

      if (_isExpiredByExpiresAt(d)) {
        tx.set(ref, <String, Object?>{
          "status": "expired",
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        throw StateError("expired");
      }

      final requestedBy = (d["requestedBy"] ?? "").toString().trim();
      final planner = (d["plannerUid"] ?? "").toString().trim();
      final plannerUid = planner.isNotEmpty
          ? planner
          : (requestedBy.isNotEmpty ? requestedBy : me.uid);

      tx.set(ref, <String, Object?>{
        "status": "accepted",
        "acceptedBy": me.uid,
        "acceptedAt": FieldValue.serverTimestamp(),
        "plannerUid": plannerUid,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (otherUid != null && otherUid.trim().isNotEmpty) {
      unawaited(PushNotifications.instance.notifyMeetupEvent(
        chatId: chatId,
        creatorUid: me.uid,
        otherUid: otherUid,
        status: "accepted",
      ));
    }
  }

  Future<void> declineMeetupRequest({
    required String chatId,
    String? otherUid,
  }) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError("Not signed in");
    final ref = meetupRef(chatId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final d = snap.data() ?? <String, dynamic>{};

      final status = (d["status"] ?? "").toString();
      if (status != "requested") return;

      tx.set(ref, <String, Object?>{
        "status": "declined",
        "declinedBy": me.uid,
        "declinedAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (otherUid != null && otherUid.trim().isNotEmpty) {
      unawaited(PushNotifications.instance.notifyMeetupEvent(
        chatId: chatId,
        creatorUid: me.uid,
        otherUid: otherUid,
        status: "declined",
      ));
    }
  }

  Future<void> cancelMeetupRequest({required String chatId}) async {
    await declineMeetupRequest(chatId: chatId);
  }

  Future<void> expireMeetupRequestIfNeeded({required String chatId}) async {
    final ref = meetupRef(chatId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final d = snap.data() ?? <String, dynamic>{};
        if ((d["status"] ?? "").toString() != "requested") return;

        if (_isExpiredByExpiresAt(d)) {
          tx.set(ref, <String, Object?>{
            "status": "expired",
            "updatedAt": FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });
    } catch (_) {}
  }

  Future<void> expireRequestBestEffort({required String chatId}) async {
    await expireMeetupRequestIfNeeded(chatId: chatId);
  }

  // -----------------------------
  // Live meetup planning / location confirmation
  // -----------------------------
  Future<Map<String, dynamic>> ensureMeetup({
    required String chatId,
    required String aUid,
    required String bUid,
    required double lat,
    required double lng,
    int? etaMinutes,
  }) async {
    final ref = meetupRef(chatId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final exists = snap.exists;
      final d = snap.data() ?? <String, dynamic>{};

      final String existingA = (d["aUid"] ?? "").toString().trim();
      final String existingB = (d["bUid"] ?? "").toString().trim();
      final bool existingPairValid = existingA.isNotEmpty && existingB.isNotEmpty;
      final bool sameSet = existingPairValid &&
          ((existingA == aUid && existingB == bUid) ||
              (existingA == bUid && existingB == aUid));

      final String finalAUid = (existingPairValid && sameSet) ? existingA : aUid;
      final String finalBUid = (existingPairValid && sameSet) ? existingB : bUid;

      final String planner = (d["plannerUid"] ?? "").toString().trim();
      final String plannerUid = planner.isNotEmpty ? planner : aUid;
      final bool callerIsPlanner = aUid == plannerUid;

      final double writeLat = callerIsPlanner
          ? lat
          : ((d["lat"] is num) ? (d["lat"] as num).toDouble() : lat);
      final double writeLng = callerIsPlanner
          ? lng
          : ((d["lng"] is num) ? (d["lng"] as num).toDouble() : lng);

      String locationStatus = (d["locationStatus"] ?? "").toString().trim();
      if (callerIsPlanner) {
        locationStatus = "proposed";
      } else if (locationStatus.isEmpty) {
        locationStatus = "none";
      }

      tx.set(ref, <String, Object?>{
        "id": chatId,
        "chatId": chatId,
        "status": "live",
        "aUid": finalAUid,
        "bUid": finalBUid,
        "plannerUid": plannerUid,
        "lat": writeLat,
        "lng": writeLng,
        if (etaMinutes != null) "etaMinutes": etaMinutes,
        "plannedAt": FieldValue.serverTimestamp(),
        "locationStatus": locationStatus,
        if (callerIsPlanner) "locationProposedBy": aUid,
        if (callerIsPlanner) "locationProposedAt": FieldValue.serverTimestamp(),
        "startedAt": (d["startedAt"] is Timestamp) ? d["startedAt"] : FieldValue.serverTimestamp(),
        "expireMinutes": (d["expireMinutes"] as int?) ?? expireMinutes,
        "expiresAt": TTLPolicy.expiresAtFromNow(TTLPolicy.meetupLiveState),
        "updatedAt": FieldValue.serverTimestamp(),
        if (!exists) "createdAt": FieldValue.serverTimestamp(),
        "aArrived": (d["aArrived"] as bool?) ?? false,
        "bArrived": (d["bArrived"] as bool?) ?? false,
        "tap": (d["tap"] is Map)
            ? d["tap"]
            : <String, Object?>{
                "aReadyAt": null,
                "bReadyAt": null,
                "verifiedAt": null,
                "windowMs": tapVerifyWindow.inMilliseconds,
                "receiptId": null,
                "method": null,
              },
      }, SetOptions(merge: true));
    });

    // Normalize expiresAt off server timestamps best-effort.
    try {
      final snap = await ref.get();
      final d = snap.data() ?? <String, dynamic>{};
      final plannedAt = d["plannedAt"];
      final createdAt = d["createdAt"];

      DateTime base;
      if (plannedAt is Timestamp) {
        base = plannedAt.toDate();
      } else if (createdAt is Timestamp) {
        base = createdAt.toDate();
      } else {
        base = DateTime.now();
      }

      await ref.set(<String, Object?>{
        "expiresAt": Timestamp.fromDate(base.add(TTLPolicy.meetupLiveState)),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    return <String, dynamic>{"id": chatId};
  }

  Future<void> confirmLocation({required String meetupId}) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError("not_signed_in");

    final ref = meetupRef(meetupId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError("not_found");
      final d = snap.data() ?? <String, dynamic>{};

      if (_isExpiredByExpiresAt(d)) throw StateError("expired");

      final aUid = (d["aUid"] ?? "").toString().trim();
      final bUid = (d["bUid"] ?? "").toString().trim();
      if (aUid.isEmpty || bUid.isEmpty) throw StateError("not_found");

      final isParticipant = me.uid == aUid || me.uid == bUid;
      if (!isParticipant) throw StateError("not_participant");

      final plannerUid = (d["plannerUid"] ?? "").toString().trim();
      if (plannerUid.isNotEmpty && me.uid == plannerUid) return;

      if (!_hasLocation(d)) throw StateError("no_location");

      final locStatus = (d["locationStatus"] ?? "").toString().trim();
      if (locStatus == "confirmed") return;

      tx.set(ref, <String, Object?>{
        "locationStatus": "confirmed",
        "locationConfirmedBy": me.uid,
        "locationConfirmedAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> markOnMyWay({required String meetupId}) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError("Not signed in");
    final ref = meetupRef(meetupId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError("not_found");
      final d = snap.data() ?? <String, dynamic>{};

      final aUid = (d["aUid"] ?? "").toString();
      final bUid = (d["bUid"] ?? "").toString();
      if (me.uid != aUid && me.uid != bUid) throw StateError("not_participant");

      final field = (me.uid == aUid) ? "aOnMyWayAt" : "bOnMyWayAt";
      tx.set(ref, <String, Object?>{
        field: FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  // -----------------------------
  // Tap-to-verify + privacy-first arrival
  // -----------------------------
  bool _tapVerified(Map<String, dynamic> meetup) {
    final tap = (meetup["tap"] is Map)
        ? Map<String, dynamic>.from(meetup["tap"] as Map)
        : <String, dynamic>{};
    return tap["verifiedAt"] is Timestamp;
  }

  Future<bool> tapToVerify({required String meetupId}) async {
    final me = _auth.currentUser;
    if (me == null) return false;

    final ref = meetupRef(meetupId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError("not_found");
      final d = snap.data() ?? <String, dynamic>{};
      if (_isExpiredByExpiresAt(d)) throw StateError("expired");

      final aUid = (d["aUid"] ?? "").toString();
      final bUid = (d["bUid"] ?? "").toString();
      final isA = me.uid == aUid;
      final isB = me.uid == bUid;
      if (!isA && !isB) throw StateError("not_participant");

      final String key = isA ? "aReadyAt" : "bReadyAt";

      tx.set(ref, <String, Object?>{
        "tap": <String, Object?>{
          key: FieldValue.serverTimestamp(),
          "windowMs": tapVerifyWindow.inMilliseconds,
        },
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    try {
      final snap = await ref.get();
      final d = snap.data() ?? <String, dynamic>{};

      final tap = (d["tap"] is Map)
          ? Map<String, dynamic>.from(d["tap"] as Map)
          : <String, dynamic>{};
      final aTs = tap["aReadyAt"];
      final bTs = tap["bReadyAt"];
      final verifiedAt = tap["verifiedAt"];

      if (verifiedAt is Timestamp) return true;
      if (aTs is! Timestamp || bTs is! Timestamp) return false;

      final diffMs =
          (aTs.toDate().difference(bTs.toDate())).inMilliseconds.abs();
      if (diffMs > tapVerifyWindow.inMilliseconds) return false;

      final lo = min(aTs.millisecondsSinceEpoch, bTs.millisecondsSinceEpoch);
      final hi = max(aTs.millisecondsSinceEpoch, bTs.millisecondsSinceEpoch);
      final receiptId = "${meetupId}:tap:${lo}:${hi}";

      await ref.set(<String, Object?>{
        "tap": <String, Object?>{
          "verifiedAt": FieldValue.serverTimestamp(),
          "receiptId": receiptId,
          "method": "tap_v1",
          "windowMs": tapVerifyWindow.inMilliseconds,
        },
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _gpsWithinRadius(Map<String, dynamic> meetup) async {
    final latAny = meetup["lat"];
    final lngAny = meetup["lng"];
    final double? lat = (latAny is num)
        ? latAny.toDouble()
        : double.tryParse((latAny ?? "").toString());
    final double? lng = (lngAny is num)
        ? lngAny.toDouble()
        : double.tryParse((lngAny ?? "").toString());
    if (lat == null || lng == null) return false;

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final granted =
          (perm == LocationPermission.always || perm == LocationPermission.whileInUse);
      if (!granted) return false;

      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return false;

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
      return d <= arrivalRadiusMeters;
    } catch (_) {
      return false;
    }
  }

  Future<ConfirmArrivalResult> confirmArrivalPrivacyFirst({required String meetupId}) async {
    final me = _auth.currentUser;
    if (me == null) return ConfirmArrivalResult.notSignedIn;

    try {
      final ref = meetupRef(meetupId);
      final snap = await ref.get();
      if (!snap.exists) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.notFound,
          message: "Meetup not found.",
        );
      }

      final d = snap.data() ?? <String, dynamic>{};
      if (_isExpiredByExpiresAt(d)) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.expired,
          message: "This meetup expired.",
        );
      }

      final String status = (d["status"] ?? "").toString();
      if (status == "completed") {
        // Safety: make sure rating window is open.
        unawaited(ensureRatingWindowOpen(meetupId));
        

        // Safety: ensure recap exists even if completion happened earlier.
        unawaited(_writeMeetupRecapIfMissing(
          chatId: meetupId,
          aUid: (d["aUid"] ?? "").toString(),
          bUid: (d["bUid"] ?? "").toString(),
          meetupDoc: d,
        ));
return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.completed,
          message: "Already completed.",
        );
      }

      final aUid = (d["aUid"] ?? "").toString().trim();
      final bUid = (d["bUid"] ?? "").toString().trim();
      if (aUid.isEmpty || bUid.isEmpty) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.notFound,
          message: "Meetup not found.",
        );
      }

      final bool isParticipant = me.uid == aUid || me.uid == bUid;
      if (!isParticipant) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.notParticipant,
          message: "Only meetup participants can confirm arrival.",
        );
      }

      final createdAt = d["createdAt"];
      if (createdAt is Timestamp) {
        final age = DateTime.now().difference(createdAt.toDate());
        if (age.isNegative || age < minConfirmAfterCreate) {
          return const ConfirmArrivalResult(
            status: ConfirmArrivalStatus.tooSoon,
            message: "Give it a moment - confirm when you're at the spot.",
          );
        }
        if (age > arrivalWindow) {
          return const ConfirmArrivalResult(
            status: ConfirmArrivalStatus.tooLate,
            message: "This meetup is too old to confirm. Plan a fresh meetup.",
          );
        }
      }

      final bool tapOk = _tapVerified(d);
      final bool gpsOk = await _gpsWithinRadius(d);

      if (!(tapOk && gpsOk)) {
        final String why = (!tapOk && !gpsOk)
            ? "Use Tap-to-Verify AND be near the pin, or use the 4-digit code."
            : (!tapOk)
                ? "Tap-to-Verify is missing. Use Tap-to-Verify (in-person) or the 4-digit code."
                : "GPS says you're not near the pin. Walk closer or use the 4-digit code.";

        return ConfirmArrivalResult(status: ConfirmArrivalStatus.failed, message: why);
      }

      return await confirmArrivalGuarded(meetupId: meetupId);
    } catch (_) {
      return const ConfirmArrivalResult(
        status: ConfirmArrivalStatus.failed,
        message: "Could not confirm arrival. Try again in a moment.",
      );
    }
  }

  Future<ConfirmArrivalResult> confirmArrivalWithCode({
    required String meetupId,
    required String code,
  }) async {
    final me = _auth.currentUser;
    if (me == null) return ConfirmArrivalResult.notSignedIn;

    final String id = meetupId.trim();
    if (id.isEmpty) {
      return const ConfirmArrivalResult(
        status: ConfirmArrivalStatus.notFound,
        message: "Meetup not found.",
      );
    }

    if (!arrivalCodeValid(id, code)) {
      return const ConfirmArrivalResult(
        status: ConfirmArrivalStatus.failed,
        message: "Code didn't match. Read it again and try once more.",
      );
    }

    return await confirmArrivalGuarded(meetupId: id);
  }

  Future<ConfirmArrivalResult> confirmArrivalGuarded({required String meetupId}) async {
    final me = _auth.currentUser;
    if (me == null) return ConfirmArrivalResult.notSignedIn;

    try {
      bool wroteArrival = false;

      await _db.runTransaction((tx) async {
        final ref = meetupRef(meetupId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw StateError("not_found");

        final d = snap.data() ?? <String, dynamic>{};
        if (_isExpiredByExpiresAt(d)) throw StateError("expired");

        final String status = (d["status"] ?? "").toString();
        if (status == "completed") return;

        final aUid = (d["aUid"] ?? "").toString();
        final bUid = (d["bUid"] ?? "").toString();
        if (aUid.isEmpty || bUid.isEmpty) throw StateError("not_found");

        final bool isParticipant = me.uid == aUid || me.uid == bUid;
        if (!isParticipant) throw StateError("not_participant");

        final createdAt = d["createdAt"];
        if (createdAt is Timestamp) {
          final age = DateTime.now().difference(createdAt.toDate());
          if (age.isNegative || age < minConfirmAfterCreate) throw StateError("too_soon");
          if (age > arrivalWindow) throw StateError("too_late");
        }

        final bool aArrived = (d["aArrived"] as bool?) ?? false;
        final bool bArrived = (d["bArrived"] as bool?) ?? false;

        if (me.uid == aUid && !aArrived) {
          wroteArrival = true;
          tx.set(ref, <String, Object?>{
            "aArrived": true,
            "aArrivedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else if (me.uid == bUid && !bArrived) {
          wroteArrival = true;
          tx.set(ref, <String, Object?>{
            "bArrived": true,
            "bArrivedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });

      final both = await _finalizeIfBothArrived(meetupId);
      if (both) {
        return ConfirmArrivalResult(
          status: ConfirmArrivalStatus.ok,
          message: "Both arrived - meetup completed.",
          bothArrived: true,
          wroteArrival: wroteArrival,
        );
      }

      return ConfirmArrivalResult(
        status: ConfirmArrivalStatus.ok,
        message: wroteArrival ? "Arrival confirmed." : "Arrival already confirmed.",
        bothArrived: false,
        wroteArrival: wroteArrival,
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains("not_found")) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.notFound,
          message: "Meetup not found.",
        );
      }
      if (msg.contains("not_participant")) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.notParticipant,
          message: "Only meetup participants can confirm arrival.",
        );
      }
      if (msg.contains("expired")) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.expired,
          message: "This meetup expired.",
        );
      }
      if (msg.contains("too_soon")) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.tooSoon,
          message: "Give it a moment - confirm when you're at the spot.",
        );
      }
      if (msg.contains("too_late")) {
        return const ConfirmArrivalResult(
          status: ConfirmArrivalStatus.tooLate,
          message: "This meetup is too old to confirm. Plan a fresh meetup.",
        );
      }

      final uid = _auth.currentUser?.uid ?? "";
      if (uid.isNotEmpty) {
        unawaited(
          OfflineOutboxService.instance.enqueueConfirmArrival(
            meetupId: meetupId,
            uid: uid,
          ),
        );
      }

      return const ConfirmArrivalResult(
        status: ConfirmArrivalStatus.failed,
        message: "Offline. We queued your arrival confirmation and will retry automatically.",
      );
    }
  }

  Future<void> confirmArrival({required String meetupId}) async {
    final res = await confirmArrivalGuarded(meetupId: meetupId);
    if (!res.isOk) throw StateError(res.message);
  }

  Future<bool> _finalizeIfBothArrived(String meetupId) async {
    try {
      final ref = meetupRef(meetupId);
      final snap = await ref.get();
      final d = snap.data();
      if (d == null) return false;

      final bool a = (d["aArrived"] as bool?) ?? false;
      final bool b = (d["bArrived"] as bool?) ?? false;
      final bool both = a && b;

      final String status = (d["status"] ?? "").toString();
      if (both && status != "completed") {
        await ref.set(<String, Object?>{
          "status": "completed",
          "completedAt": FieldValue.serverTimestamp(),

          // Always (re)open rating window on completion; normalize will refine with server completedAt.
          "ratingStartedAt": FieldValue.serverTimestamp(),
          "ratingExpiresAt": Timestamp.fromDate(DateTime.now().add(ratingWindow)),

          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Normalize rating window from completedAt (best-effort).
        unawaited(_normalizeRatingWindowFromCompletion(meetupId));

        final aUid = (d["aUid"] ?? "").toString();
        final bUid = (d["bUid"] ?? "").toString();

        // Referral gating: completing first meetup verifies referrals for either participant.
        unawaited(ReferralAttribution.instance.verifyFromMeetupCompletion(
          meetupId: meetupId,
          aUid: aUid,
          bUid: bUid,
        ));

        // Update referral progress for both participants
        if (aUid.isNotEmpty) {
          unawaited(ReferralProgressUpdater.incrementMeetupsCompleted(aUid));
        }
        if (bUid.isNotEmpty && bUid != aUid) {
          unawaited(ReferralProgressUpdater.incrementMeetupsCompleted(bUid));
        }

        if (aUid.isNotEmpty) {
          unawaited(
            PointsService.instance.recordMeetupOutcome(
              uid: aUid,
              meetupId: meetupId,
              onTime: true,
            ),
          );
        }
        if (bUid.isNotEmpty && bUid != aUid) {
          unawaited(
            PointsService.instance.recordMeetupOutcome(
              uid: bUid,
              meetupId: meetupId,
              onTime: true,
            ),
          );
        }

        final me = _auth.currentUser?.uid ?? "";
        final other = (me == aUid) ? bUid : aUid;
        if (other.isNotEmpty) {
          ReciprocityService.instance.recordMeetupCompleted(other);
          PresenceReceiptService.instance.add(
            PresenceReceipt(
              ts: DateTime.now(),
              otherUid: other,
              label: "Verified meetup",
              onTime: true,
            ),
          );
        }
      } else if (both && status == "completed") {
        // Safety: completed but rating window might be missing/expired.
        unawaited(ensureRatingWindowOpen(meetupId));
      

        // Safety: ensure recap exists even if completion happened earlier.
        unawaited(_writeMeetupRecapIfMissing(
          chatId: meetupId,
          aUid: (d["aUid"] ?? "").toString(),
          bUid: (d["bUid"] ?? "").toString(),
          meetupDoc: d,
        ));
}

      return both;
    } catch (_) {
      return false;
    }
  }

  Future<void> _normalizeRatingWindowFromCompletion(String meetupId) async {
    final ref = meetupRef(meetupId);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final snap = await ref.get();
      final d = snap.data() ?? <String, dynamic>{};

      final status = (d["status"] ?? "").toString().trim();
      final completedAt = d["completedAt"];
      if (status != "completed" || completedAt is! Timestamp) {
        unawaited(RatingsService.instance.ensureRatingWindow(meetupId));
        return;
      }

      final comp = completedAt;
      await ref.set(<String, Object?>{
        "ratingStartedAt": comp,
        "ratingExpiresAt": Timestamp.fromDate(comp.toDate().add(ratingWindow)),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      unawaited(RatingsService.instance.ensureRatingWindow(meetupId));
    }
  }

  // -----------------------------
  // Auto-expire helper (legacy meetup_live.dart)
  // -----------------------------
  Future<void> expireIfStale({required String meetupId}) async {
    final id = meetupId.trim();
    if (id.isEmpty) return;

    final ref = meetupRef(id);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final d = snap.data() ?? <String, dynamic>{};

        final String status = (d["status"] ?? "").toString();
        if (status != "live") return;

        if (_isExpiredByExpiresAt(d)) {
          tx.set(ref, <String, Object?>{
            "status": "expired",
            "updatedAt": FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return;
        }

        final bool aArrived = (d["aArrived"] as bool?) ?? false;
        final bool bArrived = (d["bArrived"] as bool?) ?? false;
        if (aArrived || bArrived) return;

        final startedAt = d["startedAt"];
        if (startedAt is! Timestamp) return;

        final int expMin = (d["expireMinutes"] as int?) ?? expireMinutes;
        final DateTime deadline = startedAt.toDate().add(Duration(minutes: expMin));
        if (DateTime.now().isBefore(deadline)) return;

        tx.set(ref, <String, Object?>{
          "status": "expired",
          "expiredAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (_) {}
  }

  // -----------------------------
  // Rating + Party helpers (used by post-meetup UI)
  // -----------------------------
  Future<void> submitThumb({
    required String chatId,
    required String raterUid,
    required String ratedUid,
    required bool thumb,
    String? reason,
  }) async {
    await RatingsService.instance
        .setThumb(chatId: chatId, thumb: thumb, reason: reason, otherUid: ratedUid);
    unawaited(PointsService.instance.touchActivity(uid: raterUid));

    unawaited(PushNotifications.instance.notifyMeetupEvent(
      chatId: chatId,
      creatorUid: raterUid,
      otherUid: ratedUid,
      status: thumb ? "rated_up" : "rated_down",
    ));
  }

  Future<void> addToParty({
    required String meUid,
    required String friendUid,
    required String source,
  }) async {
    await PartyService.instance.addToParty(friendUid, source: source);
    unawaited(PointsService.instance.touchActivity(uid: meUid));
  }
}
