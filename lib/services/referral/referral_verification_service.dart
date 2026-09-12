import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReferralVerificationService {
  ReferralVerificationService._();

  static final ReferralVerificationService instance =
      ReferralVerificationService._();

  Future<void> verifyInviteeIfEligible({
    required String inviteeUid,
    required String chatId,
    required String otherUid,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != inviteeUid) return;
    await FirebaseFunctions.instance
        .httpsCallable('syncCompletedMeetup')
        .call<void>({'meetupId': chatId});
  }
}
