import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/points_service.dart";

enum ProxFeedbackType {
  feedback,
  bug,
  comment;

  String get label {
    switch (this) {
      case ProxFeedbackType.feedback:
        return "Feedback";
      case ProxFeedbackType.bug:
        return "Bug Report";
      case ProxFeedbackType.comment:
        return "Comment";
    }
  }

  String get key {
    switch (this) {
      case ProxFeedbackType.feedback:
        return "feedback";
      case ProxFeedbackType.bug:
        return "bug";
      case ProxFeedbackType.comment:
        return "comment";
    }
  }
}

/// FeedbackService
///
/// Minimal submission pipe for tester builds.
/// Writes to /feedback/{autoId}.
///
/// Side-effects (intentional, lightweight):
/// - Touches user activity (presence/recency signal)
/// - Awards a small number of Prox Points to reinforce testing behavior
class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const int _baseRewardPoints = 2;

  Future<void> submit({
    required ProxFeedbackType type,
    required String text,
    String? firstHuhMoment,
    String source = "in_app",
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError("Not signed in");
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError("Empty feedback");
    }

    final doc = <String, Object?>{
      "uid": user.uid,
      "type": type.key,
      "text": trimmed,
      "source": source,
      "firstHuhMoment": (firstHuhMoment ?? "").trim(),
      "createdAt": FieldValue.serverTimestamp(),
    };

    await _db.collection("feedback").add(doc);

    // --- Side effects (best-effort, non-blocking) ---
    try {
      // Mark the user as active (recency signal).
      await PointsService.instance.touchActivity(uid: user.uid);

      // Light reward to encourage tester participation.
      await PointsService.instance.award(
        uid: user.uid,
        points: _baseRewardPoints,
        reason: "tester_feedback",
        category: "feedback",
      );
    } catch (_) {
      // Swallow errors: feedback submission must never fail because of rewards.
    }
  }
}
