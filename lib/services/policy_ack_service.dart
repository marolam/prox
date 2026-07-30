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

  Future<void> ensureLoaded() async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? "").trim();
    if (uid.isEmpty) return;
    if (_loadedUid == uid) return;
    final active = _loading;
    if (active != null) return active;

    final next = _loadForUid(uid);
    _loading = next;
    try {
      await next;
    } finally {
      if (identical(_loading, next)) _loading = null;
    }
  }

  Future<void> _loadForUid(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("meta")
        .doc("policyAcks")
        .get();

    _acked.clear();
    final data = doc.data();
    final versions = data?["versions"];
    if (versions is Map) {
      for (final entry in versions.entries) {
        final value = entry.value;
        if (value is Map && value["accepted"] == true) {
          _acked.add(entry.key.toString());
        } else if (value == true) {
          _acked.add(entry.key.toString());
        }
      }
    }
    _loadedUid = uid;
    notifyListeners();
  }

  bool isAcked(String version) => _acked.contains(version);

  Future<void> setAcked(
    String version,
    bool value, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? "").trim();
    if (uid.isNotEmpty) {
      _loadedUid = uid;
      final ref = FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .collection("meta")
          .doc("policyAcks");
      final field = "versions.$version";
      if (value) {
        await ref.set(
          <String, Object?>{
            field: <String, Object?>{
              "accepted": true,
              "acceptedAt": FieldValue.serverTimestamp(),
              "acceptedAtClientMs": DateTime.now().millisecondsSinceEpoch,
              ...metadata,
            },
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedAtClientMs": DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        );
      } else {
        await ref.set(
          <String, Object?>{
            field: FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedAtClientMs": DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        );
      }
    }
    if (value) {
      _acked.add(version);
    } else {
      _acked.remove(version);
    }
    notifyListeners();
  }
}
