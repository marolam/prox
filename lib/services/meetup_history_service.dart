import "package:cloud_firestore/cloud_firestore.dart";

class MeetupFavoriteLocation {
  final String id;
  final String label;
  final double lat;
  final double lng;
  final int savedAtMs;
  final String sourceMeetupId;
  final String otherUid;

  const MeetupFavoriteLocation({
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
    required this.savedAtMs,
    required this.sourceMeetupId,
    required this.otherUid,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        "id": id,
        "label": label,
        "lat": lat,
        "lng": lng,
        "savedAtMs": savedAtMs,
        "sourceMeetupId": sourceMeetupId,
        "otherUid": otherUid,
      };

  static MeetupFavoriteLocation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw["id"] ?? "").toString().trim();
    final label = (raw["label"] ?? "Favorite location").toString().trim();
    final latRaw = raw["lat"];
    final lngRaw = raw["lng"];
    final savedAtRaw = raw["savedAtMs"];

    final double? lat = latRaw is num ? latRaw.toDouble() : double.tryParse("$latRaw");
    final double? lng = lngRaw is num ? lngRaw.toDouble() : double.tryParse("$lngRaw");
    final int savedAt = savedAtRaw is int
        ? savedAtRaw
        : int.tryParse("$savedAtRaw") ?? DateTime.now().millisecondsSinceEpoch;

    if (id.isEmpty || lat == null || lng == null) return null;

    return MeetupFavoriteLocation(
      id: id,
      label: label.isEmpty ? "Favorite location" : label,
      lat: lat,
      lng: lng,
      savedAtMs: savedAt,
      sourceMeetupId: (raw["sourceMeetupId"] ?? "").toString().trim(),
      otherUid: (raw["otherUid"] ?? "").toString().trim(),
    );
  }
}

class MeetupHistoryService {
  MeetupHistoryService._();
  static final MeetupHistoryService instance = MeetupHistoryService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _historyDoc(String uid) {
    return _db.collection("users").doc(uid).collection("meta").doc("meetupHistory");
  }

  Stream<List<MeetupFavoriteLocation>> watchFavorites(String uid) {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return const Stream<List<MeetupFavoriteLocation>>.empty();

    return _historyDoc(safeUid).snapshots().map((snap) {
      final d = snap.data() ?? <String, dynamic>{};
      final raw = d["favorites"];
      if (raw is! List) return const <MeetupFavoriteLocation>[];

      final out = <MeetupFavoriteLocation>[];
      for (final item in raw) {
        final fav = MeetupFavoriteLocation.fromJson(item);
        if (fav != null) out.add(fav);
      }

      out.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
      return out;
    });
  }

  Stream<Set<String>> watchHiddenMeetupIds(String uid) {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return const Stream<Set<String>>.empty();

    return _historyDoc(safeUid).snapshots().map((snap) {
      final d = snap.data() ?? <String, dynamic>{};
      final raw = d["hiddenMeetupIds"];
      if (raw is! List) return <String>{};
      return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet();
    });
  }

  Future<void> addFavorite({
    required String uid,
    required String label,
    required double lat,
    required double lng,
    String sourceMeetupId = "",
    String otherUid = "",
  }) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = "fav_$now";
    final cleanLabel = label.trim().isEmpty ? "Favorite location" : label.trim();

    final ref = _historyDoc(safeUid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data() ?? <String, dynamic>{};
      final raw = d["favorites"];
      final current = <Object?>[];
      if (raw is List) current.addAll(raw);

      current.insert(
        0,
        MeetupFavoriteLocation(
          id: id,
          label: cleanLabel,
          lat: lat,
          lng: lng,
          savedAtMs: now,
          sourceMeetupId: sourceMeetupId.trim(),
          otherUid: otherUid.trim(),
        ).toJson(),
      );

      final trimmed = current.take(40).toList(growable: false);

      tx.set(ref, <String, Object?>{
        "favorites": trimmed,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> removeFavorite({
    required String uid,
    required String favoriteId,
  }) async {
    final safeUid = uid.trim();
    final safeId = favoriteId.trim();
    if (safeUid.isEmpty || safeId.isEmpty) return;

    final ref = _historyDoc(safeUid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data() ?? <String, dynamic>{};
      final raw = d["favorites"];
      if (raw is! List) return;

      final next = raw.where((item) {
        if (item is! Map) return true;
        return (item["id"] ?? "").toString().trim() != safeId;
      }).toList(growable: false);

      tx.set(ref, <String, Object?>{
        "favorites": next,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> hideMeetup({
    required String uid,
    required String meetupId,
  }) async {
    final safeUid = uid.trim();
    final safeMeetupId = meetupId.trim();
    if (safeUid.isEmpty || safeMeetupId.isEmpty) return;

    await _historyDoc(safeUid).set(<String, Object?>{
      "hiddenMeetupIds": FieldValue.arrayUnion(<String>[safeMeetupId]),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearHiddenMeetups({required String uid}) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return;

    await _historyDoc(safeUid).set(<String, Object?>{
      "hiddenMeetupIds": <String>[],
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
