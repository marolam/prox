import "package:cloud_firestore/cloud_firestore.dart";

class TTLPolicy {
  static const Duration deviceToken = Duration(days: 45);
  static const Duration presenceCurrent = Duration(minutes: 3);
  static const Duration meetupLiveState = Duration(hours: 12);

  static Timestamp expiresAtFromNow(Duration ttl) {
    return Timestamp.fromDate(DateTime.now().add(ttl));
  }

  static bool isExpiredTs(Timestamp ts) {
    return ts.toDate().isBefore(DateTime.now());
  }
}
