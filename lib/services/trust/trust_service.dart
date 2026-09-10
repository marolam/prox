import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TrustService {
  TrustService._();

  static final TrustService instance = TrustService._();

  Future<void> recordWouldMeetAgain({
    required bool yes,
    required String meetupId,
    required String otherUid,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to leave feedback.');
    if (meetupId.trim().isEmpty || otherUid.trim().isEmpty || otherUid == uid) {
      throw ArgumentError('A completed meetup and partner are required.');
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('trustFeedback')
        .doc(meetupId)
        .set({
          'meetupId': meetupId,
          'otherUid': otherUid,
          'wouldMeetAgain': yes,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }
}
