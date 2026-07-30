import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

/// Legacy-facing RatingService used by some screens (e.g., RatingPrompt).
/// We map to dedicated collections and keep signatures the widgets expect.
class RatingService {
  RatingService._();
  static final RatingService instance = RatingService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String _me() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError("Not signed in");
    return uid;
  }

  /// thumb: true = , false = 
  Future<void> setThumb({
    required String chatId,
    required bool thumb,
    String? reason,
  }) async {
    final uid = _me();
    final ref = _db.collection("ratings").doc(chatId).collection("entries").doc(uid);
    await ref.set({
      "raterUid": uid,
      "thumb": thumb,
      if (reason != null && reason.trim().isNotEmpty) "reason": reason.trim(),
      "ts": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// submitRating used by RatingPrompt (meetupId-centric). Stores alongside thumbs.
  Future<void> submitRating({
    required String meetupId,
    required String peerUid,
    required bool wouldMeetAgain,
    List<String>? tags,
    String? note,
    required bool bothConfirmed,
  }) async {
    final uid = _me();
    // Store under a meetups-specific bucket to avoid clashing with chatId-based ratings.
    final ref = _db.collection("ratings_meetups").doc(meetupId).collection("entries").doc(uid);
    await ref.set({
      "raterUid": uid,
      "peerUid": peerUid,
      "thumb": wouldMeetAgain,
      "tags": (tags ?? []).take(3).toList(),
      if (note != null && note.trim().isNotEmpty) "note": note.trim(),
      "bothConfirmed": bothConfirmed,
      "ts": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
