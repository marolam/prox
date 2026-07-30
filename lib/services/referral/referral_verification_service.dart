class ReferralVerificationService {
  ReferralVerificationService._();

  static final ReferralVerificationService instance = ReferralVerificationService._();

  Future<void> verifyInviteeIfEligible({
    required String inviteeUid,
    required String chatId,
    required String otherUid,
  }) async {}
}