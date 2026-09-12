import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";

class PolicyAckService extends ChangeNotifier {
  PolicyAckService._();
  static final PolicyAckService instance = PolicyAckService._();

  static const String legalAgreementVersion = "legal_terms_v1";
  static const String conductVersion = "conduct_v1";
  static const String businessRulesVersion = "business_rules_v1";

  final Set<String> _acked = <String>{};
  String? _loadedUid;
  Future<void>? _loading;
  String? _loadingUid;

  Future<void> ensureLoaded() async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? "").trim();
    if (uid.isEmpty) return;
    if (_loadedUid == uid) return;
    final active = _loading;
    if (active != null && _loadingUid == uid) return active;

    final next = _loadForUid(uid);
    _loading = next;
    _loadingUid = uid;
    try {
      await next;
    } finally {
      if (identical(_loading, next)) {
        _loading = null;
        _loadingUid = null;
      }
    }
  }

  Future<void> _loadForUid(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("meta")
        .doc("policyAcks")
        .get().timeout(const Duration(seconds: 10));

    if (FirebaseAuth.instance.currentUser?.uid != uid) return;

    _acked.clear();
    final data = doc.data();
    final versions = <String, dynamic>{
      for (final entry in (data ?? <String, dynamic>{}).entries)
        if (entry.key.startsWith("versions.")) entry.key.substring(9): entry.value,
      if (data?["versions"] is Map) ...Map<String, dynamic>.from(data!["versions"] as Map),
    };
    for (final entry in versions.entries) {
        final value = entry.value;
        if (value is Map && value["accepted"] == true) {
          _acked.add(entry.key.toString());
        } else if (value == true) {
          _acked.add(entry.key.toString());
        }
    }
    _loadedUid = uid;
    notifyListeners();
  }

  bool isAcked(String version) =>
      _loadedUid == FirebaseAuth.instance.currentUser?.uid && _acked.contains(version);

  Future<void> setAcked(
    String version,
    bool value, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? "").trim();
    if (uid.isEmpty) throw StateError("Sign in to save your policy acknowledgement.");
    if (uid.isNotEmpty) {
      final ref = FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .collection("meta")
          .doc("policyAcks");
      if (value) {
        await ref.set(
          <String, Object?>{
            "versions": <String, Object?>{version: <String, Object?>{
              ...metadata,
              "accepted": true,
              "acceptedAt": FieldValue.serverTimestamp(),
              "acceptedAtClientMs": DateTime.now().millisecondsSinceEpoch,
            }},
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedAtClientMs": DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        ).timeout(const Duration(seconds: 10));
      } else {
        await ref.set(
          <String, Object?>{
            "versions": <String, Object?>{version: FieldValue.delete()},
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedAtClientMs": DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        ).timeout(const Duration(seconds: 10));
      }
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    if (_loadedUid != uid) _acked.clear();
    _loadedUid = uid;
    if (value) {
      _acked.add(version);
    } else {
      _acked.remove(version);
    }
    notifyListeners();
  }
}
