import "dart:math";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/foundation.dart";

class ReferralCodeDoc {
  final String code;
  final bool active;
  final String referrerUid;
  final String rootReferrerUid;
  final int? remaining;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ReferralCodeDoc({
    required this.code,
    required this.active,
    required this.referrerUid,
    required this.rootReferrerUid,
    required this.remaining,
    required this.createdAt,
    required this.updatedAt,
  });

  static ReferralCodeDoc fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final bool active = (data["active"] as bool?) ?? true;
    final String referrerUid = (data["referrerUid"] as String? ?? "").trim();
    final String root = (data["rootReferrerUid"] as String? ?? "").trim();
    final int? remaining = _readInt(data["remaining"]);

    final createdTs = data["createdAt"];
    final updatedTs = data["updatedAt"];

    DateTime? createdAt;
    DateTime? updatedAt;

    if (createdTs is Timestamp) createdAt = createdTs.toDate();
    if (updatedTs is Timestamp) updatedAt = updatedTs.toDate();

    return ReferralCodeDoc(
      code: doc.id,
      active: active,
      referrerUid: referrerUid,
      rootReferrerUid: root.isNotEmpty ? root : referrerUid,
      remaining: remaining,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static int? _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

class ReferralInviteDoc {
  final String uid;
  final String status;
  final String code;
  final int meetupsCompleted;
  final int referralsCompleted;
  final bool rewardGranted;
  final bool rewardCredited;
  final DateTime? joinedAt;
  final DateTime? verifiedAt;

  const ReferralInviteDoc({
    required this.uid,
    required this.status,
    required this.code,
    required this.meetupsCompleted,
    required this.referralsCompleted,
    required this.rewardGranted,
    required this.rewardCredited,
    required this.joinedAt,
    required this.verifiedAt,
  });

  static ReferralInviteDoc fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final String status = (data["status"] as String? ?? "joined").trim();
    final String code = (data["code"] as String? ?? "").trim();
    final int meetupsCompleted =
        ReferralCodeDoc._readInt(data["meetupsCompleted"]) ?? 0;
    final int referralsCompleted =
        ReferralCodeDoc._readInt(data["referralsCompleted"]) ?? 0;
    final bool rewardGranted = (data["rewardGranted"] as bool?) ?? false;
    final bool rewardCredited = (data["rewardCredited"] as bool?) ?? false;

    final joinedTs = data["joinedAt"];
    final verifiedTs = data["verifiedAt"];

    DateTime? joinedAt;
    DateTime? verifiedAt;

    if (joinedTs is Timestamp) joinedAt = joinedTs.toDate();
    if (verifiedTs is Timestamp) verifiedAt = verifiedTs.toDate();

    return ReferralInviteDoc(
      uid: doc.id,
      status: status.isEmpty ? "joined" : status,
      code: code,
      meetupsCompleted: meetupsCompleted,
      referralsCompleted: referralsCompleted,
      rewardGranted: rewardGranted,
      rewardCredited: rewardCredited,
      joinedAt: joinedAt,
      verifiedAt: verifiedAt,
    );
  }
}

class ReferralService {
  ReferralService._({
    FirebaseFirestore? firestore,
    Random? rng,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _rng = rng ?? Random.secure();

  @visibleForTesting
  factory ReferralService.test({
    required FirebaseFirestore firestore,
    Random? rng,
  }) {
    return ReferralService._(firestore: firestore, rng: rng);
  }

  static final ReferralService _prodInstance = ReferralService._();
  static ReferralService? _testInstance;

  static ReferralService get instance => _testInstance ?? _prodInstance;

  @visibleForTesting
  static set testInstance(ReferralService? value) {
    _testInstance = value;
  }

  final FirebaseFirestore _fs;
  final Random _rng;

  static const int maxActiveCodesPerUser = 3;
  static const Duration reminderCooldown = Duration(hours: 12);

  Future<bool> getAllowInPersonQrPartyJoin(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return false;
    try {
      final snap = await _fs
          .collection("users")
          .doc(clean)
          .collection("settings")
          .doc("referral")
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      return data["allowInPersonQrPartyJoin"] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAllowInPersonQrPartyJoin(String uid, bool allowed) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    await _fs
        .collection("users")
        .doc(clean)
        .collection("settings")
        .doc("referral")
        .set(
      <String, Object?>{
        "allowInPersonQrPartyJoin": allowed,
        "updatedAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // Keep active codes in sync so attribution can trust code metadata.
    try {
      final activeCodes = await _fs
          .collection("referralCodes")
          .where("referrerUid", isEqualTo: clean)
          .where("active", isEqualTo: true)
          .get();
      for (final doc in activeCodes.docs) {
        await doc.reference.set(
          <String, Object?>{
            "allowInPersonQrPartyJoin": allowed,
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {
      // Best-effort sync only.
    }
  }

  Stream<List<ReferralCodeDoc>> streamMyCodes(String uid) {
    if (uid.trim().isEmpty) return const Stream<List<ReferralCodeDoc>>.empty();

    return _fs
        .collection("referralCodes")
        .where("referrerUid", isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final items =
          snap.docs.map(ReferralCodeDoc.fromDoc).toList(growable: false);
      final sorted = items.toList(growable: true)
        ..sort((a, b) {
          final au = a.updatedAt?.millisecondsSinceEpoch ?? 0;
          final bu = b.updatedAt?.millisecondsSinceEpoch ?? 0;
          if (au != bu) return bu.compareTo(au);
          return a.code.compareTo(b.code);
        });
      return sorted;
    });
  }

  Stream<List<ReferralInviteDoc>> streamMyInvites(String uid) {
    if (uid.trim().isEmpty)
      return const Stream<List<ReferralInviteDoc>>.empty();

    return _fs
        .collection("users")
        .doc(uid)
        .collection("referrals")
        .snapshots()
        .map((snap) {
      final items =
          snap.docs.map(ReferralInviteDoc.fromDoc).toList(growable: false);
      final sorted = items.toList(growable: true)
        ..sort((a, b) {
          final aj = a.joinedAt?.millisecondsSinceEpoch ?? 0;
          final bj = b.joinedAt?.millisecondsSinceEpoch ?? 0;
          if (aj != bj) return bj.compareTo(aj);
          return a.uid.compareTo(b.uid);
        });
      return sorted;
    });
  }

  Future<String?> createNewCode({
    required String uid,
    int remaining = 5,
    bool allowInPersonQrPartyJoin = false,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return null;

    // Prevent users from creating unbounded active codes.
    final activeCodes = await _fs
        .collection("referralCodes")
        .where("referrerUid", isEqualTo: cleanUid)
        .where("active", isEqualTo: true)
        .count()
        .get();
    if ((activeCodes.count ?? 0) >= maxActiveCodesPerUser) {
      if (kDebugMode) {
        debugPrint(
            "[ReferralService] active cap reached uid=$cleanUid count=${activeCodes.count}");
      }
      return null;
    }

    for (int attempt = 0; attempt < 6; attempt++) {
      final code = _generateCode();
      final doc = _fs.collection("referralCodes").doc(code);

      try {
        await _fs.runTransaction((tx) async {
          final snap = await tx.get(doc);
          if (snap.exists) {
            throw StateError("collision");
          }

          tx.set(
            doc,
            <String, Object?>{
              "active": true,
              "referrerUid": cleanUid,
              "rootReferrerUid": cleanUid,
              "remaining": remaining,
              "allowInPersonQrPartyJoin": allowInPersonQrPartyJoin,
              "createdAt": FieldValue.serverTimestamp(),
              "updatedAt": FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });

        if (kDebugMode)
          debugPrint("[ReferralService] created code=$code for uid=$cleanUid");
        return code;
      } catch (e) {
        if (kDebugMode)
          debugPrint("[ReferralService] createNewCode attempt=$attempt err=$e");
      }
    }

    return null;
  }

  String _generateCode() {
    const alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
    final buf = StringBuffer("PROX-");
    for (int i = 0; i < 6; i++) {
      buf.write(alphabet[_rng.nextInt(alphabet.length)]);
    }
    return buf.toString();
  }

  Future<DateTime?> getLastReminderAt({
    required String referrerUid,
    required String inviteeUid,
  }) async {
    final ru = referrerUid.trim();
    final iu = inviteeUid.trim();
    if (ru.isEmpty || iu.isEmpty) return null;

    try {
      final snap = await _fs
          .collection("users")
          .doc(ru)
          .collection("referrals")
          .doc(iu)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      final raw = data["lastReminderAt"];
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Duration> reminderCooldownLeft({
    required String referrerUid,
    required String inviteeUid,
  }) async {
    final last = await getLastReminderAt(
      referrerUid: referrerUid,
      inviteeUid: inviteeUid,
    );
    if (last == null) return Duration.zero;
    final elapsed = DateTime.now().difference(last);
    if (elapsed >= reminderCooldown) return Duration.zero;
    return reminderCooldown - elapsed;
  }

  Future<bool> canSendReminder({
    required String referrerUid,
    required String inviteeUid,
  }) async {
    final left = await reminderCooldownLeft(
      referrerUid: referrerUid,
      inviteeUid: inviteeUid,
    );
    return left <= Duration.zero;
  }

  Future<void> markReminderSent({
    required String referrerUid,
    required String inviteeUid,
  }) async {
    final ru = referrerUid.trim();
    final iu = inviteeUid.trim();
    if (ru.isEmpty || iu.isEmpty) return;

    await _fs
        .collection("users")
        .doc(ru)
        .collection("referrals")
        .doc(iu)
        .set(
      <String, Object?>{
        "lastReminderAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
