import "dart:developer" as dev;

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_storage/firebase_storage.dart";
import "package:flutter/foundation.dart";
import "package:image_picker/image_picker.dart";

class UserProfile {
  final String uid;
  final String? displayName;
  final String? photoUrl;

  final String? headline;
  final String? status;
  final String? searching;
  final String? providing;

  final List<String> searchingFor;
  final List<String> canProvide;
  final Map<String, dynamic>? keywordWorkspace;
  final Map<String, bool>? keywordSectionLocks;

  final bool isBusiness;
  final int? availabilityMinutes;
  final int? ageYears;

  final String? referrerUid;
  final String? rootReferrerUid;
  final int? partyDepth;
  final DateTime? joinedAt;
  final String? referralStatus;

  const UserProfile({
    required this.uid,
    this.displayName,
    this.photoUrl,
    this.headline,
    this.status,
    this.searching,
    this.providing,
    this.searchingFor = const <String>[],
    this.canProvide = const <String>[],
    this.keywordWorkspace,
    this.keywordSectionLocks,
    this.isBusiness = false,
    this.availabilityMinutes,
    this.ageYears,
    this.referrerUid,
    this.rootReferrerUid,
    this.partyDepth,
    this.joinedAt,
    this.referralStatus,
  });

  static String? toStringOrNull(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => toStringOrNull(e))
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static int? _readAgeYears(dynamic raw) {
    if (raw is num) {
      final int value = raw.toInt();
      if (value >= 13 && value <= 120) return value;
      return null;
    }
    if (raw is String) {
      final int? value = int.tryParse(raw.trim());
      if (value != null && value >= 13 && value <= 120) return value;
    }
    return null;
  }

  static Map<String, List<String>> _readKeywordGroups(
    Map<String, dynamic> data,
  ) {
    final dynamic raw = data["keywords"] ?? data["keywordGroups"];
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);

      final List<String> searching = _readStringList(
        m["Searching For"] ??
            m["SearchingFor"] ??
            m["searchingFor"] ??
            m["searching_for"],
      );

      final List<String> provide = _readStringList(
        m["Can Provide"] ??
            m["CanProvide"] ??
            m["canProvide"] ??
            m["can_provide"],
      );

      return <String, List<String>>{
        "Searching For": searching,
        "Can Provide": provide,
      };
    }

    final List<String> searching = _readStringList(
      data["SearchingFor"] ?? data["Searching For"],
    );
    final List<String> provide = _readStringList(
      data["CanProvide"] ?? data["Can Provide"],
    );

    return <String, List<String>>{
      "Searching For": searching,
      "Can Provide": provide,
    };
  }

  static String? _readPhotoUrlBestEffort(Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data["photoUrl"],
      data["photoURL"],
      data["photo_url"],
      data["selfieUrl"],
      data["selfieURL"],
      data["avatarUrl"],
      data["avatarURL"],
      data["photo"],
      data["avatar"],
    ];

    for (final c in candidates) {
      final s = toStringOrNull(c)?.trim();
      if (s == null || s.isEmpty) continue;
      return s;
    }
    return null;
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    final String? displayName = toStringOrNull(
      data["displayName"] ?? data["name"],
    );
    final String? photoUrl = _readPhotoUrlBestEffort(data);

    final String? headline = toStringOrNull(data["headline"]);
    final String? status = toStringOrNull(data["status"]);
    final String? searching = toStringOrNull(
      data["searchingText"] ?? data["searching"],
    );
    final String? providing = toStringOrNull(
      data["providingText"] ?? data["providing"],
    );

    final Map<String, List<String>> groups = _readKeywordGroups(data);
    final List<String> searchingFor =
        groups["Searching For"] ?? const <String>[];
    final List<String> canProvide = groups["Can Provide"] ?? const <String>[];

    Map<String, dynamic>? keywordWorkspace;
    final dynamic rawWorkspace = data["keywordWorkspace"];
    if (rawWorkspace is Map) {
      keywordWorkspace = Map<String, dynamic>.from(rawWorkspace);
    }

    Map<String, bool>? keywordSectionLocks;
    final dynamic rawLocks = data["keywordSectionLocks"];
    if (rawLocks is Map) {
      keywordSectionLocks = <String, bool>{};
      for (final entry in rawLocks.entries) {
        final k = entry.key.toString().trim();
        if (k.isEmpty) continue;
        keywordSectionLocks[k] = entry.value == true;
      }
    }

    final bool isBusiness =
        (data["businessEnabled"] as bool?) ??
        (data["isBusiness"] as bool?) ??
        false;
    final int? availabilityMinutes = (data["availabilityMinutes"] as num?)
        ?.toInt();
    final int? ageYears = _readAgeYears(data["ageYears"] ?? data["age"]);

    final String? referrerUid = toStringOrNull(data["referrer"]);
    final String? rootReferrerUid = toStringOrNull(
      data["root_referrer"] ?? data["rootReferrer"],
    );
    final int? partyDepth = (data["partyDepth"] as num?)?.toInt();

    DateTime? joinedAt;
    final dynamic joinedRaw = data["joinedAt"];
    if (joinedRaw is Timestamp) {
      joinedAt = joinedRaw.toDate();
    } else if (joinedRaw is DateTime) {
      joinedAt = joinedRaw;
    }

    final String? referralStatus = toStringOrNull(data["referralStatus"]);

    return UserProfile(
      uid: uid,
      displayName: displayName,
      photoUrl: photoUrl,
      headline: headline,
      status: status,
      searching: searching,
      providing: providing,
      searchingFor: searchingFor,
      canProvide: canProvide,
      keywordWorkspace: keywordWorkspace,
      keywordSectionLocks: keywordSectionLocks,
      isBusiness: isBusiness,
      availabilityMinutes: availabilityMinutes,
      ageYears: ageYears,
      referrerUid: referrerUid,
      rootReferrerUid: rootReferrerUid,
      partyDepth: partyDepth,
      joinedAt: joinedAt,
      referralStatus: referralStatus,
    );
  }

  factory UserProfile.fromDoc(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return UserProfile.fromMap(uid, data);
  }

  bool get hasMinimumKeywords =>
      searchingFor.isNotEmpty && canProvide.isNotEmpty;
}

class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  final Map<String, UserProfile> _profileCache = <String, UserProfile>{};
  int _sessionRevision = 0;

  void clearSession() {
    _sessionRevision++;
    _profileCache.clear();
    uploadDebug.value = const ProfileUploadDebugState();
  }

  void _cacheProfile(String uid, UserProfile profile) {
    _profileCache.remove(uid);
    _profileCache[uid] = profile;
    if (_profileCache.length > 200)
      _profileCache.remove(_profileCache.keys.first);
  }

  final ValueNotifier<ProfileUploadDebugState> uploadDebug =
      ValueNotifier<ProfileUploadDebugState>(const ProfileUploadDebugState());

  static const String _storageBucketOverride = String.fromEnvironment(
    "PROX_STORAGE_BUCKET",
  );

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final FirebaseStorage _storage = _createStorage();

  Future<List<String>> _filterModeratedKeywords(List<String> values) async {
    final normalized = values
        .map(
          (value) => value.trim().toLowerCase().replaceAll(RegExp(r"\s+"), " "),
        )
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) return const <String>[];
    final hidden = <String>{};
    for (var start = 0; start < normalized.length; start += 10) {
      final end = (start + 10).clamp(0, normalized.length);
      final snap = await _db
          .collection("keywordModeration")
          .where("normalizedKeyword", whereIn: normalized.sublist(start, end))
          .get();
      hidden.addAll(
        snap.docs
            .where((doc) => doc.data()["hidden"] == true)
            .map((doc) => (doc.data()["normalizedKeyword"] ?? "").toString()),
      );
    }
    return normalized.where((value) => !hidden.contains(value)).toList();
  }

  DocumentReference<Map<String, dynamic>> _usersRef(String uid) =>
      _db.doc("users/$uid");
  DocumentReference<Map<String, dynamic>> _profilesRef(String uid) =>
      _db.doc("publicProfiles/$uid");

  FirebaseStorage _createStorage() {
    final raw = _storageBucketOverride.trim();
    if (raw.isEmpty) return FirebaseStorage.instance;
    final String bucket = raw.startsWith("gs://") ? raw : "gs://$raw";
    return FirebaseStorage.instanceFor(bucket: bucket);
  }

  void _updateUploadDebug({
    String? uid,
    String? bucket,
    String? path,
    String? status,
    String? error,
  }) {
    final prev = uploadDebug.value;
    uploadDebug.value = prev.copyWith(
      uid: uid,
      bucket: bucket,
      path: path,
      status: status,
      error: error,
      lastUpdated: DateTime.now(),
    );
  }

  String _niceStorageUploadError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    if (error is FirebaseException && error.code == "canceled") {
      return "Photo upload was canceled.";
    }

    if ((error is FirebaseException && error.code == "unauthenticated") ||
        lower.contains("request had invalid authentication credentials")) {
      return "Photo upload failed because the user is not authenticated. Please sign in again and retry.";
    }

    if ((error is FirebaseException &&
            (error.code == "unauthorized" ||
                error.code == "permission-denied")) ||
        lower.contains("httpresult: 403") ||
        lower.contains("permission denied") ||
        lower.contains("does not have permission")) {
      return "Storage permission denied (HTTP 403). Verify Storage rules allow authenticated writes to profiles/{uid}/... and confirm the app is using the intended bucket.";
    }

    // Firebase Storage 412 from GCS when the Firebase bucket service account is not correctly linked.
    if (lower.contains("httpresult: 412") ||
        lower.contains("code\": 412") ||
        lower.contains("missing necessary permissions") ||
        lower.contains("re-linking your firebase bucket")) {
      return "Storage backend is misconfigured (HTTP 412). In Firebase Console, open Storage and re-link/repair the bucket service account permissions, then retry.";
    }

    if (error is FirebaseException) {
      final message = (error.message ?? "").trim();
      if (message.isNotEmpty) {
        return "Storage upload failed (${error.code}): $message";
      }
      return "Storage upload failed (${error.code}).";
    }

    return "Storage upload failed: $raw";
  }

  bool _isMe(String uid) {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    return me.isNotEmpty && me == uid;
  }

  UserProfile? peekCachedProfile(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return null;
    return _profileCache[u];
  }

  Stream<UserProfile?> watchProfile(String uid) {
    final String u = uid.trim();
    if (u.isEmpty) return const Stream<UserProfile?>.empty();
    final viewer = FirebaseAuth.instance.currentUser?.uid;
    final revision = _sessionRevision;
    bool currentSession() =>
        revision == _sessionRevision &&
        viewer != null &&
        FirebaseAuth.instance.currentUser?.uid == viewer;

    if (_isMe(u)) {
      return _usersRef(u).snapshots().map((snap) {
        if (!snap.exists || !currentSession()) return null;
        final p = UserProfile.fromDoc(u, snap);
        _cacheProfile(u, p);
        return p;
      });
    }

    return _profilesRef(u).snapshots().map((snap) {
      if (!snap.exists || !currentSession()) return null;
      final p = UserProfile.fromDoc(u, snap);
      _cacheProfile(u, p);
      return p;
    });
  }

  Future<UserProfile?> getProfileOnce(String uid) async {
    final String u = uid.trim();
    if (u.isEmpty) return null;
    final viewer = FirebaseAuth.instance.currentUser?.uid;
    final revision = _sessionRevision;
    bool currentSession() =>
        revision == _sessionRevision &&
        viewer != null &&
        FirebaseAuth.instance.currentUser?.uid == viewer;
    if (!currentSession()) return null;

    try {
      if (_isMe(u)) {
        final snap = await _usersRef(u).get();
        if (!snap.exists || !currentSession()) return null;
        final p = UserProfile.fromDoc(u, snap);
        _cacheProfile(u, p);
        return p;
      }

      final snap = await _profilesRef(u).get();
      if (!snap.exists || !currentSession()) return null;
      final p = UserProfile.fromDoc(u, snap);
      _cacheProfile(u, p);
      return p;
    } catch (_) {
      return null;
    }
  }

  /// Profile photo upload (web-safe).
  ///
  /// Compatibility:
  /// - New callers should pass `XFile` from image_picker.
  /// - Older callers that pass a dart:io File will still compile because this accepts `Object`.
  ///   We read bytes dynamically (no dart:io import here).
  Future<String> uploadProfilePhoto({
    required String uid,
    required Object file,
  }) async {
    final String? me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me.isEmpty) {
      throw StateError("Photo upload failed: user is not signed in.");
    }
    if (me != uid) {
      throw StateError(
        "Photo upload failed: auth uid mismatch (me=$me target=$uid).",
      );
    }

    dev.log(
      "[Profile] uploadProfilePhoto begin uid=$uid bucket=${_storage.bucket}",
      name: "prox.profile",
    );
    _updateUploadDebug(
      uid: uid,
      bucket: _storage.bucket,
      status: "starting",
      error: null,
      path: null,
    );

    Uint8List bytes;

    if (file is XFile) {
      bytes = await file.readAsBytes();
    } else {
      // Legacy: accept anything that has `readAsBytes()`.
      final dynamic any = file;
      final dynamic b = await any.readAsBytes();
      bytes = b as Uint8List;
    }

    final String name = "profile_${DateTime.now().millisecondsSinceEpoch}.jpg";
    final List<String> candidatePaths = <String>[
      "profiles/$uid/$name",
      // Back-compat fallback for older bucket rules/deploys.
      "users/$uid/$name",
    ];

    Object? lastError;
    for (final path in candidatePaths) {
      try {
        _updateUploadDebug(path: path, status: "uploading", error: null);
        dev.log(
          "[Profile] uploadProfilePhoto attempt path=$path bucket=${_storage.bucket}",
          name: "prox.profile",
        );
        final ref = _storage.ref(path);
        await ref.putData(bytes, SettableMetadata(contentType: "image/jpeg"));
        dev.log(
          "[Profile] uploadProfilePhoto success path=$path",
          name: "prox.profile",
        );
        _updateUploadDebug(path: path, status: "uploaded", error: null);
        return ref.getDownloadURL();
      } catch (e) {
        _updateUploadDebug(path: path, status: "failed", error: e.toString());
        dev.log(
          "[Profile] uploadProfilePhoto failed path=$path error=$e",
          name: "prox.profile",
        );
        lastError = e;
      }
    }

    _updateUploadDebug(
      status: "failed",
      error: _niceStorageUploadError(lastError ?? "unknown storage error"),
    );
    throw StateError(
      _niceStorageUploadError(lastError ?? "unknown storage error"),
    );
  }

  String _niceFirestoreError(FirebaseException e) {
    final code = e.code;
    final msg = (e.message ?? "").trim();

    if (code == "permission-denied")
      return "Permission denied by Firestore rules.";
    if (code == "unavailable")
      return "Network issue (Firestore unavailable). Try again.";
    if (code == "failed-precondition")
      return "Firestore precondition failed (often an index or offline state).";
    if (code == "invalid-argument")
      return "Invalid data sent to Firestore (bad field type/size).";
    if (code == "resource-exhausted")
      return "Quota/resource exhausted (Firestore throttling).";
    if (msg.isNotEmpty) return "Firestore error ($code): $msg";
    return "Firestore error ($code).";
  }

  Future<void> upsertProfile({
    required String uid,
    String? displayName,
    String? photoUrl,
    String? headline,
    String? searchingText,
    String? providingText,
    List<String>? searchingFor,
    List<String>? canProvide,
    Map<String, dynamic>? keywordWorkspace,
    Map<String, bool>? keywordSectionLocks,
    Map<String, dynamic>? keywordMetrics,
    bool? isBusiness,
    int? availabilityMinutes,
    int? ageYears,
  }) async {
    if (searchingFor != null) {
      searchingFor = await _filterModeratedKeywords(searchingFor);
    }
    if (canProvide != null) {
      canProvide = await _filterModeratedKeywords(canProvide);
    }
    final userRef = _usersRef(uid);
    final payload = <String, Object?>{};

    if (displayName != null) {
      payload["displayName"] = displayName;
      payload["name"] = displayName;
    }
    if (photoUrl != null) {
      payload["photoUrl"] = photoUrl;
      payload["selfieUrl"] = photoUrl;
      payload["photoURL"] = photoUrl;
    }
    if (headline != null) payload["headline"] = headline;
    if (searchingText != null) payload["searchingText"] = searchingText;
    if (providingText != null) payload["providingText"] = providingText;

    if (searchingFor != null || canProvide != null) {
      final groups = <String, Object?>{};
      if (searchingFor != null) groups["Searching For"] = searchingFor;
      if (canProvide != null) groups["Can Provide"] = canProvide;

      payload["keywords"] = groups;

      if (searchingFor != null) payload["SearchingFor"] = searchingFor;
      if (canProvide != null) payload["CanProvide"] = canProvide;
    }

    if (keywordWorkspace != null) {
      payload["keywordWorkspace"] = keywordWorkspace;
    }

    if (keywordSectionLocks != null) {
      payload["keywordSectionLocks"] = keywordSectionLocks;
    }

    if (keywordMetrics != null) {
      payload["keywordMetrics"] = keywordMetrics;
    }

    if (isBusiness != null) payload["businessEnabled"] = isBusiness;
    if (availabilityMinutes != null)
      payload["availabilityMinutes"] = availabilityMinutes;
    if (ageYears != null) {
      payload["ageYears"] = ageYears;
      payload["age"] = ageYears;
    }

    payload["updatedAt"] = FieldValue.serverTimestamp();

    try {
      await userRef.set(payload, SetOptions(merge: true));
    } on FirebaseException catch (e, st) {
      dev.log(
        "[Profile] upsert /users/$uid failed code=${e.code} message=${e.message ?? ""}",
        name: "prox.profile",
        error: e,
        stackTrace: st,
      );
      throw StateError(_niceFirestoreError(e));
    } catch (e, st) {
      dev.log(
        "[Profile] upsert /users/$uid unexpected error: $e",
        name: "prox.profile",
        error: e,
        stackTrace: st,
      );
      throw StateError("Unknown error saving profile. Details: $e");
    }

    // The server publishes an allowlisted discovery profile after this save.
  }
}

class ProfileUploadDebugState {
  final String? uid;
  final String? bucket;
  final String? path;
  final String? status;
  final String? error;
  final DateTime? lastUpdated;

  const ProfileUploadDebugState({
    this.uid,
    this.bucket,
    this.path,
    this.status,
    this.error,
    this.lastUpdated,
  });

  ProfileUploadDebugState copyWith({
    String? uid,
    String? bucket,
    String? path,
    String? status,
    String? error,
    DateTime? lastUpdated,
  }) {
    return ProfileUploadDebugState(
      uid: uid ?? this.uid,
      bucket: bucket ?? this.bucket,
      path: path ?? this.path,
      status: status ?? this.status,
      error: error,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
