class ReferralAttribution {
  ReferralAttribution._();
  static final ReferralAttribution instance = ReferralAttribution._();

  Future<void> verifyFromMeetupCompletion({
    required String meetupId,
    required String aUid,
    required String bUid,
  }) async {}

  Future<bool> applyIfPossible({String explicitUid = "", String uid = ""}) async => false;

  Future<void> markProfileComplete({required String uid}) async {}
}
