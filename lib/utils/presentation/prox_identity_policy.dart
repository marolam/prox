import "package:flutter/foundation.dart";

import "package:prox/services/user_profile_service.dart";

/// Phase 2: Identity presentation rules (no schema changes).
///
/// Locked decisions:
/// - Alias-only until Party or meetup threshold.
/// - Tree is invisible; most discovery surfaces should NOT reveal real names.
/// - Party scope may reveal real names.
///
/// We implement this as a pure presentation policy.
/// Callers pass context like "isPartyScope" when they know it.
class ProxIdentityPolicy {
  ProxIdentityPolicy._();

  /// Returns a safe, human-friendly display label for a given profile + uid.
  ///
  /// If [isPartyScope] is false, we prefer alias-like presentation and do not
  /// reveal `displayName` even if present.
  static String displayName({
    required String uid,
    required UserProfile? profile,
    required bool isPartyScope,
  }) {
    if (isPartyScope) {
      final dn = (profile?.displayName ?? "").trim();
      if (dn.isNotEmpty) return dn;
    }

    // Alias-first: never show true displayName outside Party scope.
    // Use a stable, non-identifying fallback.
    final handle = _aliasFromProfile(profile);
    if (handle.isNotEmpty) return handle;

    return fallbackAlias(uid);
  }

  /// Lightweight "alias" field inference without schema change.
  /// If you later add a dedicated alias field, wire it here only.
  static String _aliasFromProfile(UserProfile? p) {
    // Best-effort: headline or searchingFor can act as a "tagline" in the future,
    // but for now keep alias strict and simple.
    // If a user already uses displayName as an alias, we STILL treat it as hidden
    // unless Party scope is true.
    // So we do not use displayName here.
    return "";
  }

  static String fallbackAlias(String uid) {
    final s = uid.trim();
    if (s.isEmpty) return "Prox user";
    final n = s.length >= 6 ? 6 : s.length;
    final slug = s.substring(0, n);
    return "User $slug";
  }

  /// Debug helper for logs/tooling only.
  @visibleForTesting
  static String debugResolved(UserProfile? p, {required bool isPartyScope}) {
    return "party=$isPartyScope displayName='${p?.displayName}'";
  }
}
