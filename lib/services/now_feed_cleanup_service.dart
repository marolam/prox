import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";

class NowFeedCleanupResult {
  final int matchesDeleted;
  final int meetupsDeleted;

  const NowFeedCleanupResult({
    required this.matchesDeleted,
    required this.meetupsDeleted,
  });

  int get totalDeleted => matchesDeleted + meetupsDeleted;
}

/// Keeps Nearby culture focused on now by pruning stale meetups/matches.
class NowFeedCleanupService {
  NowFeedCleanupService._();
  static final NowFeedCleanupService instance = NowFeedCleanupService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static const Duration _autoSweepInterval = Duration(minutes: 20);
  static const Duration _manualMatchRetention = Duration(hours: 6);
  static const Duration _nonPartyNoMeetupRetention = Duration(minutes: 60);
  static const Duration _nonPartyPostMeetupRetention = Duration(hours: 12);
  static const Duration _manualMeetupCompletedRetention = Duration(hours: 8);
  static const Duration _manualMeetupStaleRetention = Duration(hours: 3);

  DateTime? _lastAutoSweepAt;

  Future<NowFeedCleanupResult?> pruneAutoIfDue(String uid) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return null;

    final now = DateTime.now();
    final last = _lastAutoSweepAt;
    if (last != null && now.difference(last) < _autoSweepInterval) {
      return null;
    }
    _lastAutoSweepAt = now;
    return pruneNow(cleanUid);
  }

  Future<NowFeedCleanupResult> pruneNow(String uid) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      return const NowFeedCleanupResult(matchesDeleted: 0, meetupsDeleted: 0);
    }

    final int matchesDeleted = await _pruneMatches(cleanUid);
    final int meetupsDeleted = await _pruneMeetups(cleanUid);

    return NowFeedCleanupResult(
      matchesDeleted: matchesDeleted,
      meetupsDeleted: meetupsDeleted,
    );
  }

  Future<int> _pruneMatches(String uid) async {
    final now = DateTime.now();
    final cutoff = now.subtract(_manualMatchRetention);
    final partyUids = await _loadPartyMemberUids(uid);
    final completedMeetupOthers = await _loadCompletedMeetupOthers(uid);

    final snap = await _fs
        .collection("matches")
        .where("participants", arrayContains: uid)
        .limit(300)
        .get();

    final staleDocs = <DocumentReference<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final otherUid = _otherUidFromMatchDoc(uid: uid, docId: doc.id, data: d);
      final ts = _pickDocDate(d, keys: const ["updatedAt", "lastUpdate", "createdAt"]);

      // Non-party matches should naturally expire.
      if (otherUid.isNotEmpty && !partyUids.contains(otherUid)) {
        final bool hadMeetupButNoParty = completedMeetupOthers.contains(otherUid);
        final retention = hadMeetupButNoParty ? _nonPartyPostMeetupRetention : _nonPartyNoMeetupRetention;
        final nonPartyCutoff = now.subtract(retention);
        if (ts == null || ts.isAfter(nonPartyCutoff)) continue;
        staleDocs.add(doc.reference);
        continue;
      }

      if (ts == null || ts.isAfter(cutoff)) continue;
      staleDocs.add(doc.reference);
    }

    if (staleDocs.isEmpty) return 0;

    int deleted = 0;
    for (final chunk in _chunk(staleDocs, 200)) {
      final batch = _fs.batch();
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
      deleted += chunk.length;
    }

    return deleted;
  }

  Future<Set<String>> _loadPartyMemberUids(String uid) async {
    final snap = await _fs.collection("users").doc(uid).collection("party").limit(500).get();
    final out = <String>{};
    for (final doc in snap.docs) {
      final id = doc.id.trim();
      if (id.isEmpty || id == "current" || id == "partySettings") continue;
      out.add(id);
    }
    return out;
  }

  Future<Set<String>> _loadCompletedMeetupOthers(String uid) async {
    final out = <String>{};

    final a = await _fs.collection("meetups").where("aUid", isEqualTo: uid).limit(500).get();
    final b = await _fs.collection("meetups").where("bUid", isEqualTo: uid).limit(500).get();

    for (final doc in a.docs) {
      final d = doc.data();
      final status = (d["status"] ?? "").toString().trim().toLowerCase();
      if (status != "completed") continue;
      final other = (d["bUid"] ?? "").toString().trim();
      if (other.isNotEmpty && other != uid) out.add(other);
    }

    for (final doc in b.docs) {
      final d = doc.data();
      final status = (d["status"] ?? "").toString().trim().toLowerCase();
      if (status != "completed") continue;
      final other = (d["aUid"] ?? "").toString().trim();
      if (other.isNotEmpty && other != uid) out.add(other);
    }

    return out;
  }

  String _otherUidFromMatchDoc({
    required String uid,
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final partsDyn = (data["participants"] as List<dynamic>?) ?? const <dynamic>[];
    final parts = partsDyn.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList(growable: false);
    for (final p in parts) {
      if (p != uid) return p;
    }

    if (docId.contains("__")) {
      final split = docId.split("__");
      if (split.length == 2) {
        return split[0] == uid ? split[1].trim() : split[0].trim();
      }
    }

    return "";
  }

  Future<int> _pruneMeetups(String uid) async {
    final a = await _fs.collection("meetups").where("aUid", isEqualTo: uid).limit(300).get();
    final b = await _fs.collection("meetups").where("bUid", isEqualTo: uid).limit(300).get();

    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final d in a.docs) d.id: d,
      for (final d in b.docs) d.id: d,
    };

    final now = DateTime.now();
    final staleRefs = <DocumentReference<Map<String, dynamic>>>[];

    for (final doc in byId.values) {
      final d = doc.data();
      final status = (d["status"] ?? "").toString().trim().toLowerCase();

      if (status == "live") continue;

      final bool completed = status == "completed";
      final retention = completed ? _manualMeetupCompletedRetention : _manualMeetupStaleRetention;
      final cutoff = now.subtract(retention);

      final ts = _pickDocDate(
        d,
        keys: const ["completedAt", "updatedAt", "createdAt"],
      );
      if (ts == null || ts.isAfter(cutoff)) continue;
      staleRefs.add(doc.reference);
    }

    if (staleRefs.isEmpty) return 0;

    int deleted = 0;
    for (final chunk in _chunk(staleRefs, 200)) {
      final batch = _fs.batch();
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
      deleted += chunk.length;
    }

    return deleted;
  }

  DateTime? _pickDocDate(
    Map<String, dynamic> data, {
    required List<String> keys,
  }) {
    for (final k in keys) {
      final v = data[k];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) {
        final dt = DateTime.fromMillisecondsSinceEpoch(v, isUtc: false);
        return dt;
      }
    }
    return null;
  }

  Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (int i = 0; i < items.length; i += size) {
      final end = (i + size < items.length) ? i + size : items.length;
      yield items.sublist(i, end);
    }
  }
}
