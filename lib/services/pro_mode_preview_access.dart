import "package:firebase_auth/firebase_auth.dart";

import "package:prox/release/release_flags.dart";

class ProModePreviewAccess {
  ProModePreviewAccess._();
  static final ProModePreviewAccess instance = ProModePreviewAccess._();

  bool isAllowedForCurrentUser() {
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {
      return false;
    }
    return isAllowed(
      uid: user?.uid,
      email: user?.email,
      allowlist: ReleaseFlags.proModePreviewLogins,
      previewEnabled: ReleaseFlags.proModePreviewEnabled,
    );
  }

  static bool isAllowed({
    required String? uid,
    required String? email,
    required String allowlist,
    required bool previewEnabled,
  }) {
    if (!previewEnabled) return false;
    final uidKey = _normalize(uid);
    final emailKey = _normalize(email);
    if (uidKey.isEmpty && emailKey.isEmpty) return false;

    final allowed = allowlist
        .split(RegExp(r"[,;\s]+"))
        .map(_normalize)
        .where((value) => value.isNotEmpty)
        .toSet();

    return allowed.contains(uidKey) || allowed.contains(emailKey);
  }

  static String _normalize(String? raw) => (raw ?? "").trim().toLowerCase();
}
