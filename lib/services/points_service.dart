import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_functions/cloud_functions.dart";

import "package:cloud_firestore/cloud_firestore.dart";

class PointsMeta {
  const PointsMeta({
    required this.currentPoints,
    required this.totalPoints,
    required this.completedMeetups,
    required this.trustPercent,
    this.referrals = 0,
    this.supportSessions = 0,
  });

  static const PointsMeta empty = PointsMeta(
    currentPoints: 0,
    totalPoints: 0,
    completedMeetups: 0,
    trustPercent: 0,
  );

  final int currentPoints;
  final int totalPoints;
  final int completedMeetups;
  final double trustPercent;
  final int referrals;
  final int supportSessions;

  int get level => (totalPoints ~/ 100) + 1;

  PointsMeta copyWith({
    int? currentPoints,
    int? totalPoints,
    int? completedMeetups,
    double? trustPercent,
    int? referrals,
    int? supportSessions,
  }) {
    return PointsMeta(
      currentPoints: currentPoints ?? this.currentPoints,
      totalPoints: totalPoints ?? this.totalPoints,
      completedMeetups: completedMeetups ?? this.completedMeetups,
      trustPercent: trustPercent ?? this.trustPercent,
      referrals: referrals ?? this.referrals,
      supportSessions: supportSessions ?? this.supportSessions,
    );
  }
}

/// The server is the sole authority for balances, rewards and spending.
class PointsService {
  PointsService._();
  static final PointsService instance = PointsService._();
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final Map<String, PointsMeta> _cache = {};

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _fs.collection("users").doc(uid).collection("meta").doc("points");

  static PointsMeta fromData(Map<String, dynamic> data) => PointsMeta(
    currentPoints: (data["currentPoints"] as num?)?.toInt() ?? 0,
    totalPoints: (data["totalPoints"] as num?)?.toInt() ?? 0,
    completedMeetups: (data["completedMeetups"] as num?)?.toInt() ?? 0,
    trustPercent: (data["trustPercent"] as num?)?.toDouble() ?? 0,
    referrals: (data["referrals"] as num?)?.toInt() ?? 0,
    supportSessions: (data["supportSessions"] as num?)?.toInt() ?? 0,
  );

  PointsMeta peekMeta(String uid) => _cache[uid] ?? PointsMeta.empty;

  Stream<PointsMeta> watchMeta(String uid) {
    final clean = uid.trim();
    if (clean.isEmpty) return Stream.value(PointsMeta.empty);
    return _ref(clean).snapshots().map((snapshot) {
      final meta = fromData(snapshot.data() ?? {});
      if (FirebaseAuth.instance.currentUser?.uid == clean) _cache[clean] = meta;
      return meta;
    });
  }

  Stream<PointsMeta> streamMySnapshot() =>
      watchMeta(FirebaseAuth.instance.currentUser?.uid ?? "");

  Future<void> refreshMeta(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    final snapshot = await _ref(clean).get().timeout(const Duration(seconds: 10));
    if (FirebaseAuth.instance.currentUser?.uid == clean) {
      _cache[clean] = fromData(snapshot.data() ?? {});
    }
  }

  Future<PointsMeta> getMeta(String uid) async {
    await refreshMeta(uid);
    return peekMeta(uid);
  }

  void clearSession() => _cache.clear();

  Future<void> addPoints({required String uid, required int amount,
    String? reason, String? sourceId, String category = "",
    String contextId = "", String contextType = "",
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError("Sign in again to continue.");
    final source = contextId.isNotEmpty ? contextId : sourceId ?? contextType;
    if (source.isEmpty || !{"policy_ack", "support", "feedback"}.contains(category)) {
      throw StateError("Points are awarded only for activity verified by Prox.");
    }
    // Amount is deliberately not sent: rewards are calculated and deduplicated by the server.
    await FirebaseFunctions.instanceFor(region: "us-central1")
        .httpsCallable("claimVerifiedReward").call<dynamic>({"category": category, "contextId": source});
    await refreshMeta(uid);
  }

  Future<void> award({required String uid, required int points,
    String? reason, String category = "", String contextId = "",
  }) => addPoints(uid: uid, amount: points, reason: reason,
      category: category, contextId: contextId);

  Future<bool> spendPoints({required String uid, required int amount,
    String? reason, String? sourceId, String category = "",
    String contextId = "", String contextType = "",
  }) async {
    throw StateError("Use a verified store purchase to spend points.");
  }

  Future<void> touchActivity({required String uid}) => refreshMeta(uid);

  // Rewards follow server-validated meetup/rating documents; these methods only refresh.
  Future<void> recordMeetupOutcome({required String uid, required String meetupId,
    required bool onTime}) => refreshMeta(uid);
  Future<void> recordMeetupRating({required String uid, required String chatId,
    required bool thumbsUp}) => refreshMeta(uid);
}
