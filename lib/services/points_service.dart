import "dart:async";

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

class PointsService {
  PointsService._();
  static final PointsService instance = PointsService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final Map<String, PointsMeta> _cache = <String, PointsMeta>{};
  final Map<String, StreamController<PointsMeta>> _controllers =
      <String, StreamController<PointsMeta>>{};

  StreamController<PointsMeta> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<PointsMeta>.broadcast(),
    );
  }

  PointsMeta peekMeta(String uid) => _cache[uid] ?? PointsMeta.empty;

  Stream<PointsMeta> watchMeta(String uid) async* {
    yield peekMeta(uid);
    yield* _controllerFor(uid).stream;
  }

  Stream<PointsMeta> streamMySnapshot() {
    return _controllerFor("__me__").stream;
  }

  Future<void> refreshMeta(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    try {
      final snap = await _fs
          .collection("users")
          .doc(clean)
          .collection("points")
          .doc("meta")
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      final next = PointsMeta(
        currentPoints: (data["currentPoints"] as num?)?.toInt() ?? 0,
        totalPoints: (data["totalPoints"] as num?)?.toInt() ?? 0,
        completedMeetups: (data["completedMeetups"] as num?)?.toInt() ?? 0,
        trustPercent: (data["trustPercent"] as num?)?.toDouble() ?? 0,
        referrals: (data["referrals"] as num?)?.toInt() ?? 0,
        supportSessions: (data["supportSessions"] as num?)?.toInt() ?? 0,
      );
      _emit(clean, next);
    } catch (_) {
      _emit(clean, peekMeta(clean));
    }
  }

  Future<PointsMeta> getMeta(String uid) async {
    await refreshMeta(uid);
    return peekMeta(uid);
  }

  Future<void> addPoints({
    required String uid,
    required int amount,
    String? reason,
    String? sourceId,
    String category = "",
    String contextId = "",
    String contextType = "",
  }) async {
    final current = peekMeta(uid);
    final safe = amount < 0 ? 0 : amount;
    final next = current.copyWith(
      currentPoints: current.currentPoints + safe,
      totalPoints: current.totalPoints + safe,
    );
    await _persist(uid, next);
  }

  Future<void> award({
    required String uid,
    required int points,
    String? reason,
    String category = "",
  }) {
    return addPoints(
      uid: uid,
      amount: points,
      reason: reason,
      category: category,
    );
  }

  Future<bool> spendPoints({
    required String uid,
    required int amount,
    String? reason,
    String? sourceId,
    String category = "",
    String contextId = "",
    String contextType = "",
  }) async {
    final current = peekMeta(uid);
    final safe = amount < 0 ? 0 : amount;
    if (current.currentPoints < safe) return false;

    final next = current.copyWith(currentPoints: current.currentPoints - safe);
    await _persist(uid, next);
    return true;
  }

  Future<void> touchActivity({required String uid}) async {
    await refreshMeta(uid);
  }

  Future<void> recordMeetupOutcome({
    required String uid,
    required String meetupId,
    required bool onTime,
  }) async {
    final current = peekMeta(uid);
    final next = current.copyWith(
      completedMeetups: current.completedMeetups + 1,
      trustPercent: onTime
          ? (current.trustPercent < 100 ? current.trustPercent + 1 : 100)
          : current.trustPercent,
    );
    await _persist(uid, next);
  }

  Future<void> recordMeetupRating({
    required String uid,
    required String chatId,
    required bool thumbsUp,
  }) async {
    final current = peekMeta(uid);
    final double delta = thumbsUp ? 0.5 : -0.5;
    final trust = (current.trustPercent + delta).clamp(0, 100).toDouble();
    await _persist(uid, current.copyWith(trustPercent: trust));
  }

  Future<void> _persist(String uid, PointsMeta meta) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;

    _emit(clean, meta);

    try {
      await _fs
          .collection("users")
          .doc(clean)
          .collection("points")
          .doc("meta")
          .set(<String, dynamic>{
        "currentPoints": meta.currentPoints,
        "totalPoints": meta.totalPoints,
        "completedMeetups": meta.completedMeetups,
        "trustPercent": meta.trustPercent,
        "referrals": meta.referrals,
        "supportSessions": meta.supportSessions,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Keep local cache in sync even when persistence fails.
    }
  }

  void _emit(String uid, PointsMeta meta) {
    _cache[uid] = meta;
    final c = _controllerFor(uid);
    if (!c.isClosed) {
      c.add(meta);
    }
    final me = _controllerFor("__me__");
    if (!me.isClosed) {
      me.add(meta);
    }
  }
}
