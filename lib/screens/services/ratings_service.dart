import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/points_service.dart";
import "package:prox/services/reciprocity/reciprocity_service.dart";

class RatingsService {
  RatingsService._();
  static final RatingsService instance = RatingsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const Duration ratingWindow = Duration(hours: 24);

  DocumentReference<Map<String, dynamic>> _meetupRef(String meetupDocId) {
    return _db.collection("meetups").doc(meetupDocId);
  }

  DocumentReference<Map<String, dynamic>> _entryRef({
    required String chatId,
    required String uid,
  }) {
    return _db.collection("ratings").doc(chatId).collection("entries").doc(uid);
  }

  /// Create rating window only if missing (does NOT extend an open window).
  Future<void> ensureRatingWindow(String meetupDocId) async {
    final id = meetupDocId.trim();
    if (id.isEmpty) return;

    final ref = _meetupRef(id);

    // If startedAt missing, create it (serverTimestamp) + provisional expires.
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final d = snap.data() ?? <String, dynamic>{};
        final started = d["ratingStartedAt"];
        if (started is Timestamp) return;

        tx.set(
          ref,
          <String, Object?>{
            "ratingStartedAt": FieldValue.serverTimestamp(),
            "ratingExpiresAt": Timestamp.fromDate(DateTime.now().add(ratingWindow)),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (_) {}

    await repairExpiresFromStarted(id);
  }

  /// Always repair ratingExpiresAt from ratingStartedAt (server-authoritative).
  Future<void> repairExpiresFromStarted(String meetupDocId) async {
    final id = meetupDocId.trim();
    if (id.isEmpty) return;

    final ref = _meetupRef(id);

    try {
      final snap = await ref.get();
      final d = snap.data() ?? <String, dynamic>{};
      final started = d["ratingStartedAt"];
      if (started is Timestamp) {
        await ref.set(
          <String, Object?>{
            "ratingExpiresAt": Timestamp.fromDate(started.toDate().add(ratingWindow)),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }

  /// Force-open a fresh rating window ONLY when the current window is closed/expired,
  /// and only when the meetup is "complete enough":
  /// - status == "completed" OR (aArrived && bArrived)
  ///
  /// Also finalizes the meetup if both arrived but status is still live.
  Future<void> forceReopenWindowIfClosedAndCompleted(String meetupDocId) async {
    final id = meetupDocId.trim();
    if (id.isEmpty) return;

    final ref = _meetupRef(id);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final d = snap.data() ?? <String, dynamic>{};

        final status = (d["status"] ?? "").toString().trim();
        final bool aArrived = (d["aArrived"] as bool?) ?? false;
        final bool bArrived = (d["bArrived"] as bool?) ?? false;

        final bool completedEnough = status == "completed" || (aArrived && bArrived);
        if (!completedEnough) return;

        // Finalize if both arrived but status hasn't flipped yet.
        if (aArrived && bArrived && status != "completed") {
          tx.set(
            ref,
            <String, Object?>{
              "status": "completed",
              "completedAt": FieldValue.serverTimestamp(),
              "updatedAt": FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        final exp = d["ratingExpiresAt"];
        final bool expired = (exp is Timestamp) ? DateTime.now().isAfter(exp.toDate()) : true;
        if (!expired) return; // do not extend an open window

        // Reset startedAt; delete expires so stale old value can't survive.
        tx.set(
          ref,
          <String, Object?>{
            "ratingStartedAt": FieldValue.serverTimestamp(),
            "ratingExpiresAt": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (_) {}

    // Let serverTimestamp land, then repair expires from started.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await repairExpiresFromStarted(id);
  }

  Future<bool> isRatingWindowOpen(String meetupDocId) async {
    final id = meetupDocId.trim();
    if (id.isEmpty) return true;

    try {
      final snap = await _meetupRef(id).get();
      final d = snap.data();
      if (d == null) return true;

      final exp = d["ratingExpiresAt"];
      if (exp is Timestamp) {
        return DateTime.now().isBefore(exp.toDate());
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setThumb({
    required String chatId,
    required bool thumb,
    String? reason,
    String? otherUid,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _entryRef(chatId: chatId, uid: uid).set(
      <String, Object?>{
        "thumb": thumb,
        "reason": reason,
        "ts": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (otherUid != null && otherUid.trim().isNotEmpty) {
      ReciprocityService.instance.recordThumbGiven(otherUid.trim());
    }

    try {
      if (thumb) {
        await PointsService.instance.recordMeetupRating(uid: uid, chatId: chatId, thumbsUp: true);
      }
      await PointsService.instance.touchActivity(uid: uid);
    } catch (_) {}
  }

  Future<Map<String, Object?>?> getMyEntry({required String chatId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final snap = await _entryRef(chatId: chatId, uid: uid).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyEntry({required String chatId}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _entryRef(chatId: chatId, uid: uid).snapshots();
  }
}
