import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/services/points_service.dart';

/// The completion trigger owns counts; the client refreshes its receipt.
class ReferralProgressUpdater {
  static Future<void> incrementMeetupsCompleted(String uid) async {
    if (FirebaseAuth.instance.currentUser?.uid == uid) {
      await PointsService.instance.refreshMeta(uid);
    }
  }
}
