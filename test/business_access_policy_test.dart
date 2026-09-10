import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/business_mode/business_access_policy.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8);
  test(
    'monthly flags without a valid future expiration do not grant access',
    () {
      for (final expiry in [
        null,
        'invalid',
        Timestamp.fromDate(now),
        Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      ]) {
        expect(
          BusinessAccessPolicy.hasAccess({
            'businessSubscriptionActive': true,
            'subscriptionRenewsAt': expiry,
            'businessModeActive': true,
            'testerUnlocked': true,
          }, now: now),
          isFalse,
        );
      }
    },
  );
  test('confirmed lifetime and unexpired prepaid access are accepted', () {
    expect(
      BusinessAccessPolicy.hasAccess({'businessPurchased': true}, now: now),
      isTrue,
    );
    expect(
      BusinessAccessPolicy.hasAccess({
        'businessSubscriptionActive': true,
        'subscriptionRenewsAt': Timestamp.fromDate(
          now.add(const Duration(days: 1)),
        ),
      }, now: now),
      isTrue,
    );
    expect(
      BusinessAccessPolicy.hasAccess({
        'businessSubscriptionActive': false,
        'subscriptionRenewsAt': Timestamp.fromDate(
          now.add(const Duration(days: 1)),
        ),
      }, now: now),
      isFalse,
    );
  });
}
