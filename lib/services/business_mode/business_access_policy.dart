import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessAccessPolicy {
  static bool hasActivePrepaid(Map<String, dynamic> data, {DateTime? now}) {
    final expires = data['subscriptionRenewsAt'];
    return data['businessSubscriptionActive'] == true &&
        expires is Timestamp &&
        expires.toDate().isAfter(now ?? DateTime.now());
  }

  static bool hasAccess(Map<String, dynamic> data, {DateTime? now}) =>
      data['businessPurchased'] == true || hasActivePrepaid(data, now: now);
}
