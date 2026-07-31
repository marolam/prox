import "package:firebase_auth/firebase_auth.dart";
import "package:prox/release/rollout_gate_service.dart";
import "package:prox/screens/services/monetization_service.dart";
import "package:prox/services/business_mode/business_mode_state_service.dart";
import "package:prox/services/pro_mode_preview_access.dart";

class BusinessEntitlementSnapshot {
  const BusinessEntitlementSnapshot({
    required this.uid,
    required this.paidUnlocked,
    required this.testerUnlocked,
    required this.businessModeActive,
  });

  final String uid;
  final bool paidUnlocked;
  final bool testerUnlocked;
  final bool businessModeActive;

  bool get canOperateBusiness =>
      (paidUnlocked || testerUnlocked) && businessModeActive;
}

class BusinessEntitlementGuard {
  BusinessEntitlementGuard._();
  static final BusinessEntitlementGuard instance = BusinessEntitlementGuard._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String requireSignedInUid({String? uid}) {
    final String resolved = (uid ?? _auth.currentUser?.uid ?? "").trim();
    if (resolved.isEmpty) {
      throw StateError("You must be signed in to use Pro Mode.");
    }
    return resolved;
  }

  void ensureWriteRolloutEnabled() {
    if (!RolloutGateService.instance.isBusinessModeWriteEnabled) {
      throw StateError(RolloutGateService.instance.businessModeDisabledReason);
    }
  }

  Future<BusinessEntitlementSnapshot> loadSnapshot({String? uid}) async {
    final String resolvedUid = requireSignedInUid(uid: uid);
    if (!ProModePreviewAccess.instance.isAllowedForCurrentUser()) {
      throw StateError("Pro Mode preview is not available for this account.");
    }
    final bool paidUnlocked =
        await MonetizationService.instance.isBusinessUnlocked(resolvedUid);
    final bool testerUnlocked =
        await BusinessModeStateService.instance.isTesterUnlocked(resolvedUid);
    final bool active =
        await BusinessModeStateService.instance.isActive(resolvedUid);

    return BusinessEntitlementSnapshot(
      uid: resolvedUid,
      paidUnlocked: paidUnlocked,
      testerUnlocked: testerUnlocked,
      businessModeActive: active,
    );
  }

  Future<BusinessEntitlementSnapshot> ensureCanOperateBusiness(
      {String? uid}) async {
    ensureWriteRolloutEnabled();
    final snapshot = await loadSnapshot(uid: uid);
    if (!snapshot.canOperateBusiness) {
      if (!snapshot.paidUnlocked && !snapshot.testerUnlocked) {
        throw StateError(
          "Pro Mode subscription required. Personal mode can discover Pros but cannot operate as a Pro.",
        );
      }
      throw StateError(
          "Pro Mode is unlocked but not active. Activate Pro Mode to continue.");
    }
    return snapshot;
  }
}
