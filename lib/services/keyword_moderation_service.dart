import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

class KeywordModerationService {
  KeywordModerationService._();
  static final KeywordModerationService instance = KeywordModerationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String normalize(String keyword) =>
      keyword.trim().toLowerCase().replaceAll(RegExp(r"\s+"), " ");

  Stream<Set<String>> watchSuppressedKeywords() {
    final uid = _auth.currentUser?.uid ?? "";
    if (uid.isEmpty) return Stream<Set<String>>.value(const <String>{});
    final global = _db
        .collection("keywordModeration")
        .where("hidden", isEqualTo: true)
        .limit(500)
        .snapshots();
    final mine = _db
        .collection("users")
        .doc(uid)
        .collection("hiddenKeywords")
        .limit(500)
        .snapshots();
    return global.asyncExpand((globalSnap) {
      final globallyHidden = globalSnap.docs
          .map((doc) =>
              normalize((doc.data()["normalizedKeyword"] ?? "").toString()))
          .where((keyword) => keyword.isNotEmpty)
          .toSet();
      return mine.map((mineSnap) => <String>{
            ...globallyHidden,
            ...mineSnap.docs
                .map((doc) => normalize(
                    (doc.data()["normalizedKeyword"] ?? "").toString()))
                .where((keyword) => keyword.isNotEmpty),
          });
    });
  }

  Future<void> report({
    required String keyword,
    required String targetUid,
    required String role,
    String reason = "misleading_or_low_quality",
  }) async {
    final reporterUid = _auth.currentUser?.uid ?? "";
    final normalized = normalize(keyword);
    final target = targetUid.trim();
    if (reporterUid.isEmpty || normalized.isEmpty || target.isEmpty) return;

    final reportId = "${reporterUid}_${target}_${normalized.hashCode.abs()}";
    final batch = _db.batch();
    batch.set(_db.collection("keywordReports").doc(reportId), <String, Object?>{
      "reporterUid": reporterUid,
      "targetUid": target,
      "keyword": keyword.trim(),
      "normalizedKeyword": normalized,
      "role": role,
      "reason": reason,
      "status": "submitted",
      "createdAt": FieldValue.serverTimestamp(),
    });
    batch.set(
      _db
          .collection("users")
          .doc(reporterUid)
          .collection("hiddenKeywords")
          .doc(reportId),
      <String, Object?>{
        "normalizedKeyword": normalized,
        "targetUid": target,
        "hiddenAt": FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }
}
