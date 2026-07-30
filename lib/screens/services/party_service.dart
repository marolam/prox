import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "dart:math";

import "package:prox/services/first_user_journey/first_user_journey_service.dart";
import "package:prox/services/offline/offline_outbox_service.dart";
import "package:prox/utils/geo.dart";

class PartyMemberEntry {
  final String otherUid;
  final DateTime? since;
  final bool mutual;
  final String source;

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
      mutual: d["mutual"] == true,
      source: (d["source"] ?? "").toString(),
    );
  }
}

class PartyService {
  PartyService._();
  static final PartyService instance = PartyService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Random _rng = Random.secure();
  static const double _inPersonMaxDistanceMeters = 120.0;
  static const Duration _presenceFreshness = Duration(minutes: 5);

  CollectionReference<Map<String, dynamic>> _party(String uid) =>
      _db.collection("users").doc(uid).collection("party");

  bool _isPartyMemberDocId(String docId) {
    final id = docId.trim();
    if (id.isEmpty) return false;
    // Reserved metadata docs that are not user UIDs.
    if (id == "current" || id == "partySettings") return false;
    return true;
  }

  CollectionReference<Map<String, dynamic>> get _meetupRequests =>
      _db.collection("meetupRequests");

  String _presenceDocId(String uid) => "party_presence_$uid";

  String _pairDocId(String a, String b) {
    final ids = <String>[a.trim(), b.trim()]..sort();
    return "party_handshake_${ids[0]}_${ids[1]}";
  }

  String _genInPersonCode() {
    final value = _rng.nextInt(900000) + 100000;
    return value.toString();
  }

  Future<String> startInPersonDirectInviteSession({
    Duration ttl = const Duration(minutes: 3),
  }) async {
    final uid = _me();
    final code = _genInPersonCode();
    final now = DateTime.now();

    await _meetupRequests.doc(_presenceDocId(uid)).set(
      <String, Object?>{
        "kind": "partyPresence",
        "uid": uid,
        "code": code,
        "active": true,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
        "expiresAt": Timestamp.fromDate(now.add(ttl)),
      },
      SetOptions(merge: true),
    );

    return code;
  }

  Future<void> stopInPersonDirectInviteSession() async {
    final uid = _me();
    await _meetupRequests.doc(_presenceDocId(uid)).set(
      <String, Object?>{
        "active": false,
        "updatedAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<InPersonDirectInviteResult> confirmInPersonDirectInviteCode(String rawCode) async {
    final me = _me();
    final code = rawCode.trim();
    if (code.length < 4) {
      return const InPersonDirectInviteResult(
        ok: false,
        paired: false,
        message: "Enter the code shown on the other person's screen.",
      );
    }

    final now = DateTime.now();
    final presenceSnap = await _meetupRequests
        .where("kind", isEqualTo: "partyPresence")
        .where("code", isEqualTo: code)
        .where("active", isEqualTo: true)
        .limit(5)
        .get();

    String peerUid = "";
    for (final doc in presenceSnap.docs) {
      final data = doc.data();
      final uid = (data["uid"] ?? "").toString().trim();
      if (uid.isEmpty || uid == me) continue;

      final expires = data["expiresAt"];
      if (expires is Timestamp && expires.toDate().isBefore(now)) {
        continue;
      }

      peerUid = uid;
      break;
    }

    if (peerUid.isEmpty) {
      return const InPersonDirectInviteResult(
        ok: false,
        paired: false,
        message: "No active nearby Party code found. Ask them to reopen Direct Invite.",
      );
    }

    final proximity = await _validateInPersonProximity(me: me, peerUid: peerUid, now: now);
    if (!proximity.ok) {
      return InPersonDirectInviteResult(
        ok: false,
        paired: false,
        peerUid: peerUid,
        message: proximity.message,
        proximity: proximity,
      );
    }

    final pairRef = _meetupRequests.doc(_pairDocId(me, peerUid));
    final ids = <String>[me, peerUid]..sort();
    final aUid = ids[0];
    final bUid = ids[1];
    final bool iAmA = me == aUid;

    bool pairedNow = false;
    await _db.runTransaction((tx) async {
      final pairSnap = await tx.get(pairRef);
      final cur = pairSnap.data() ?? <String, dynamic>{};
      final Timestamp expiryTs = Timestamp.fromDate(now.add(const Duration(minutes: 4)));

      bool aConfirmed = cur["aConfirmed"] == true;
      bool bConfirmed = cur["bConfirmed"] == true;

      if (iAmA) {
        aConfirmed = true;
      } else {
        bConfirmed = true;
      }

      pairedNow = aConfirmed && bConfirmed;

      tx.set(
        pairRef,
        <String, Object?>{
          "kind": "partyHandshake",
          "aUid": aUid,
          "bUid": bUid,
          "aConfirmed": aConfirmed,
          "bConfirmed": bConfirmed,
          "paired": pairedNow,
          "expiresAt": expiryTs,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    await addToParty(peerUid, source: "inPersonDirectInvite");

    if (pairedNow) {
      await stopInPersonDirectInviteSession();
      await _meetupRequests.doc(_presenceDocId(peerUid)).set(
        <String, Object?>{
          "active": false,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return InPersonDirectInviteResult(
        ok: true,
        paired: true,
        peerUid: peerUid,
        message: "Paired in person. You are now in each other's Party.",
        proximity: proximity,
      );
    }

    return InPersonDirectInviteResult(
      ok: true,
      paired: false,
      peerUid: peerUid,
      message: "Step 1 done. Ask them to enter your code to complete pairing.",
      proximity: proximity,
    );
  }

  Future<InPersonProximityCheck> _validateInPersonProximity({
    required String me,
    required String peerUid,
    required DateTime now,
  }) async {
    final myPresence = await _readPresencePoint(me);
    final peerPresence = await _readPresencePoint(peerUid);

    if (myPresence == null || peerPresence == null) {
      return const InPersonProximityCheck(
        ok: false,
        message: "Couldn't verify physical presence. Both users must have fresh location sharing.",
      );
    }

    final myAge = now.difference(myPresence.ts);
    final peerAge = now.difference(peerPresence.ts);
    if (myAge > _presenceFreshness || peerAge > _presenceFreshness) {
      return InPersonProximityCheck(
        ok: false,
        message: "Location is stale. Both users should open Nearby/Party and retry.",
        mePresenceAgeSec: myAge.inSeconds,
        peerPresenceAgeSec: peerAge.inSeconds,
      );
    }

    final distanceMeters = haversineMeters(
      myPresence.lat,
      myPresence.lon,
      peerPresence.lat,
      peerPresence.lon,
    );
    if (distanceMeters > _inPersonMaxDistanceMeters) {
      return InPersonProximityCheck(
        ok: false,
        message: "Too far apart for in-person pairing. Move closer and retry.",
        distanceMeters: distanceMeters,
        mePresenceAgeSec: myAge.inSeconds,
        peerPresenceAgeSec: peerAge.inSeconds,
      );
    }

    return InPersonProximityCheck(
      ok: true,
      message: "In-person proximity verified.",
      distanceMeters: distanceMeters,
      mePresenceAgeSec: myAge.inSeconds,
      peerPresenceAgeSec: peerAge.inSeconds,
    );
  }

  Future<_PresencePoint?> _readPresencePoint(String uid) async {
    final snap = await _db.collection("users").doc(uid).collection("presence").doc("current").get();
    final data = snap.data();
    if (data == null) return null;

    double? lat;
    double? lon;
    final gp = data["geopoint"];
    if (gp is GeoPoint) {
      lat = gp.latitude;
      lon = gp.longitude;
    } else {
      lat = _toDouble(data["lat"]);
      lon = _toDouble(data["lon"]);
    }

    if (lat == null || lon == null) return null;

    final ts = _readDateTime(data["ts"]) ??
        _readDateTime(data["updatedAt"]) ??
        _readDateTime(data["createdAt"]);
    final at = ts ?? DateTime.fromMillisecondsSinceEpoch(0);
    return _PresencePoint(lat: lat, lon: lon, ts: at);
  }

  DateTime? _readDateTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) {
      final parsedInt = int.tryParse(v);
      if (parsedInt != null) return DateTime.fromMillisecondsSinceEpoch(parsedInt);
      return DateTime.tryParse(v);
    }
    return null;
  }

  double? _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Future<void> syncReferralInPersonAutoJoins() async {
    final uid = _me();
    final referrals = await _db
        .collection("users")
        .doc(uid)
        .collection("referrals")
        .where("partyInPersonQrRequested", isEqualTo: true)
        .limit(100)
        .get();

    for (final doc in referrals.docs) {
      final data = doc.data();
      if (data["partyInPersonQrGrantedAt"] != null) continue;

      final inviteeUid = (data["uid"] ?? doc.id).toString().trim();
      if (inviteeUid.isEmpty || inviteeUid == uid) continue;

      await addToParty(inviteeUid, source: "referralInPersonQrReferrer");
      await doc.reference.set(
        <String, Object?>{
          "partyInPersonQrGrantedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

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
    return snap.exists;
  }

  /// Live stream for "is other in my party?"
  Stream<bool> watchIsInMyParty(String otherUid) {
    final uid = _me();
    final other = otherUid.trim();
    if (other.isEmpty) return const Stream<bool>.empty();
    return _party(uid).doc(other).snapshots().map((s) => s.exists);
  }

  /// Canonical Party list stream: reads /users/{uid}/party/*
  Stream<List<PartyMemberEntry>> watchMyPartyEntries() async* {
    // Emit immediately so Party UI never blocks indefinitely on first snapshot.
    yield const <PartyMemberEntry>[];

    yield* _auth.authStateChanges().asyncExpand((user) {
      final uid = user?.uid ?? "";
      if (uid.trim().isEmpty) {
        return Stream<List<PartyMemberEntry>>.value(const <PartyMemberEntry>[]);
      }

      return _party(uid).snapshots().map((qs) {
        final out = <PartyMemberEntry>[];
        for (final doc in qs.docs) {
          if (!_isPartyMemberDocId(doc.id)) continue;
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
      });
    });
  }

  Future<void> addToParty(
    String otherUid, {
    String source = "postMeetup",
  }) async {
    final uid = _me();
    final other = otherUid.trim();
    if (other.isEmpty) return;

    final myRef = _party(uid).doc(other);
    final theirRef = _party(other).doc(uid);

    // Always write my party entry (queue if offline/fails).
    try {
      await myRef.set(
        {
          "since": FieldValue.serverTimestamp(),
          "sinceClientMs": DateTime.now().millisecondsSinceEpoch,
          "mutual": false,
          "source": source,
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      await OfflineOutboxService.instance.enqueueSet(
        docPath: myRef.path,
        data: <String, Object?>{
          "sinceClientMs": DateTime.now().millisecondsSinceEpoch,
          "mutual": false,
          "source": source,
        },
        idempotencyKey: "party_${uid}_${other}",
      );
      return;
    }

    try {
      FirstUserJourneyService.instance.markInviteFriend(uid);
    } catch (_) {}

    // Mutual best-effort: if they already added you, flip mutual on both docs.
    try {
      final theirSnap = await theirRef.get();
      if (theirSnap.exists) {
        await _db.runTransaction((tx) async {
          tx.set(myRef, {"mutual": true}, SetOptions(merge: true));
          tx.set(theirRef, {"mutual": true}, SetOptions(merge: true));
        });
      }
    } catch (_) {}
  }

  /// Best-effort: if both sides have added each other, force mutual=true on both docs.
  /// Heals older tester data where mutual couldn't be written due to rules.
  Future<void> reconcileMutual(String otherUid) async {
    final uid = _me();
    final other = otherUid.trim();
    if (other.isEmpty) return;

    final myRef = _party(uid).doc(other);
    final theirRef = _party(other).doc(uid);

    try {
      final mySnap = await myRef.get();
      final theirSnap = await theirRef.get();
      if (!mySnap.exists || !theirSnap.exists) return;

      final myData = mySnap.data() ?? <String, dynamic>{};
      final theirData = theirSnap.data() ?? <String, dynamic>{};

      final bool myMutual = myData["mutual"] == true;
      final bool theirMutual = theirData["mutual"] == true;

      if (myMutual && theirMutual) return;

      await _db.runTransaction((tx) async {
        tx.set(myRef, {"mutual": true}, SetOptions(merge: true));
        tx.set(theirRef, {"mutual": true}, SetOptions(merge: true));
      });
    } catch (_) {
      // ignore (best-effort)
    }
  }

  Stream<bool> watchMutual(String otherUid) {
    final uid = _me();
    final other = otherUid.trim();
    if (other.isEmpty) return const Stream<bool>.empty();

    return _party(uid).doc(other).snapshots().map((s) {
      final d = s.data();
      return d != null && (d["mutual"] == true);
    });
  }

  Future<void> removeFromParty(String otherUid) async {
    final uid = _me();
    final other = otherUid.trim();
    if (other.isEmpty) return;

    final myRef = _party(uid).doc(other);
    final theirRef = _party(other).doc(uid);

    await _db.runTransaction((tx) async {
      // Read before any writes in this transaction to avoid Firestore assertions.
      final theirSnap = await tx.get(theirRef);

      tx.delete(myRef);

      if (theirSnap.exists) {
        tx.set(theirRef, {"mutual": false}, SetOptions(merge: true));
      }
    });
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

class _PresencePoint {
  final double lat;
  final double lon;
  final DateTime ts;

  const _PresencePoint({
    required this.lat,
    required this.lon,
    required this.ts,
  });
}