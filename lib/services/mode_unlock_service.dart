import "package:prox/services/points_service.dart";
import "package:prox/services/business_mode/business_mode_policy_service.dart";

class ModeUnlockState {
  const ModeUnlockState({
    required this.canUseBusiness,
    required this.verifiedReferrals,
    required this.completedMeetups,
    required this.neededForBusiness,
  });

  final bool canUseBusiness;
  final int verifiedReferrals;
  final int completedMeetups;
  final int neededForBusiness;
}

class ModeUnlockService {
  ModeUnlockService._();
  static final ModeUnlockService instance = ModeUnlockService._();

  Future<ModeUnlockState?> loadForUser(String uid) async {
    final meta = await PointsService.instance.getMeta(uid);
    final completed = meta.completedMeetups;
    final referrals = meta.referrals;
    const requiredMeetups = BusinessModePolicyService.minCompletedMeetups;
    const requiredReferrals = BusinessModePolicyService.minVerifiedReferrals;
    final needed = (requiredMeetups - completed).clamp(0, requiredMeetups);
    final referralNeeded =
        (requiredReferrals - referrals).clamp(0, requiredReferrals);
    final decision = BusinessModePolicyService.instance.evaluate(meta);

    return ModeUnlockState(
      canUseBusiness: decision.eligible,
      verifiedReferrals: referrals,
      completedMeetups: completed,
      neededForBusiness: needed + referralNeeded,
    );
  }
}
