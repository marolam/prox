import "package:prox/services/business_mode/business_mode_state_service.dart";
import "package:prox/services/monetization_service.dart";
import "package:prox/services/points_service.dart";
import "package:prox/services/pro_mode_preview_access.dart";
import "package:prox/services/progression_service.dart";
import "package:prox/widgets/business_mode_gate.dart";

class BusinessModeEligibility {
  static const int minPoints = 25;
  static const double minTrustPercent = 40;
  static const int minCompletedMeetups = 1;

  static bool isEligibleFromMeta(PointsMeta m) {
    return (m.trustPercent >= minTrustPercent) &&
        (m.totalPoints >= minPoints) &&
        (m.completedMeetups >= minCompletedMeetups);
  }

  static BusinessGateState gateFromMeta(PointsMeta m) {
    return isEligibleFromMeta(m)
        ? BusinessGateState.eligible
        : BusinessGateState.locked;
  }

  /// Paid access is confirmed by the server; progression only enables the offer.
  static Future<BusinessGateState> gateForUser({
    required String uid,
    required PointsMeta meta,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return BusinessGateState.locked;
    if (!ProModePreviewAccess.instance.isAllowedForCurrentUser()) {
      return BusinessGateState.locked;
    }

    // Canonical paid unlock path: billing entitlements.
    final monetizationUnlocked = await MonetizationService.instance
        .isBusinessUnlocked(cleanUid);
    if (monetizationUnlocked) {
      final active = await BusinessModeStateService.instance.isActive(cleanUid);
      return active ? BusinessGateState.active : BusinessGateState.eligible;
    }

    final progression = await ProgressionService.instance.loadForUser(uid);
    final progressionEligible =
        progression?.has(ProxFeatureUnlock.businessMode) ?? false;
    final eligible = progressionEligible && isEligibleFromMeta(meta);
    if (!eligible) return BusinessGateState.locked;

    return BusinessGateState.eligible;
  }
}
