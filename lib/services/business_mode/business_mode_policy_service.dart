import "package:prox/services/points_service.dart";

class BusinessModePolicyDecision {
  final bool eligible;
  final String reason;

  const BusinessModePolicyDecision({
    required this.eligible,
    required this.reason,
  });
}

class BusinessModePolicyService {
  BusinessModePolicyService._();
  static final BusinessModePolicyService instance =
      BusinessModePolicyService._();

  // Phase 1 hard gate: proven trust plus verified-user activity.
  static const double minTrustPercent = 80;
  static const int minCompletedMeetups = 5;
  static const int minVerifiedReferrals = 5;
  static const int minPoints = 0;

  BusinessModePolicyDecision evaluate(PointsMeta meta) {
    if (meta.trustPercent < minTrustPercent) {
      return const BusinessModePolicyDecision(
        eligible: false,
        reason: "Pro Mode requires at least 80% trust.",
      );
    }

    if (meta.completedMeetups < minCompletedMeetups) {
      return const BusinessModePolicyDecision(
        eligible: false,
        reason: "Pro Mode requires at least 5 completed meetups.",
      );
    }

    if (meta.referrals < minVerifiedReferrals) {
      return const BusinessModePolicyDecision(
        eligible: false,
        reason: "Pro Mode requires at least 5 verified referrals.",
      );
    }

    if (meta.totalPoints < minPoints) {
      return const BusinessModePolicyDecision(
        eligible: false,
        reason: "Pro Mode requirements are not met.",
      );
    }

    return const BusinessModePolicyDecision(
      eligible: true,
      reason: "Eligible for Pro Mode.",
    );
  }
}
