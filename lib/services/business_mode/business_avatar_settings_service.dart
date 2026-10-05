import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/user_settings_service.dart";

const String defaultBusinessAvatarReply =
    "Thanks for reaching out! I am away right now and will reply when I am available.";

class BusinessAvatarSettings {
  const BusinessAvatarSettings({
    required this.enabled,
    required this.reply,
  });

  final bool enabled;
  final String reply;
}

abstract class BusinessAvatarSettingsStore {
  Future<BusinessAvatarSettings> loadForCurrentUser();

  Future<void> saveForCurrentUser({
    required bool enabled,
    required String reply,
  });
}

class BusinessAvatarSettingsService implements BusinessAvatarSettingsStore {
  BusinessAvatarSettingsService._();

  static final BusinessAvatarSettingsService instance =
      BusinessAvatarSettingsService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  String _requireUid() {
    final uid = (_auth.currentUser?.uid ?? "").trim();
    if (uid.isEmpty) {
      throw StateError("Sign in to manage your business avatar reply.");
    }
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _avatarDoc(String uid) {
    return _fs
        .collection("users")
        .doc(uid)
        .collection("business")
        .doc("settings")
        .collection("items")
        .doc("avatar");
  }

  @override
  Future<BusinessAvatarSettings> loadForCurrentUser() async {
    final uid = _requireUid();
    final local = UserSettingsService.instance.current;
    final snap = await _avatarDoc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));

    final data = snap.data() ?? const <String, dynamic>{};
    final enabled =
        (data["enabled"] as bool?) ?? local.businessAvatarEnabled;
    final storedReply = (data["reply"] ?? "").toString().trim();
    final localReply = (local.businessAvatarNote ?? "").trim();
    final reply = storedReply.isNotEmpty
        ? storedReply
        : (localReply.isNotEmpty ? localReply : defaultBusinessAvatarReply);

    UserSettingsService.instance
      ..setBusinessAvatarEnabled(enabled)
      ..setBusinessAvatarNote(reply);

    return BusinessAvatarSettings(enabled: enabled, reply: reply);
  }

  @override
  Future<void> saveForCurrentUser({
    required bool enabled,
    required String reply,
  }) async {
    final uid = _requireUid();
    final cleanReply = reply.trim();
    if (cleanReply.isEmpty) {
      throw StateError("Reply message cannot be empty.");
    }

    await _avatarDoc(uid).set(<String, dynamic>{
      "enabled": enabled,
      "reply": cleanReply,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    UserSettingsService.instance
      ..setBusinessAvatarEnabled(enabled)
      ..setBusinessAvatarNote(cleanReply);
  }
}
