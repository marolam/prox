import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/business_mode/business_entitlement_guard.dart';

void main() {
  test('a legacy tester flag never unlocks paid operations', () {
    expect(
      const BusinessEntitlementSnapshot(
        uid: 'user',
        paidUnlocked: false,
        testerUnlocked: true,
        businessModeActive: true,
      ).canOperateBusiness,
      isFalse,
    );
  });
  test('paid access must also be activated', () {
    expect(
      const BusinessEntitlementSnapshot(
        uid: 'user',
        paidUnlocked: true,
        testerUnlocked: false,
        businessModeActive: false,
      ).canOperateBusiness,
      isFalse,
    );
    expect(
      const BusinessEntitlementSnapshot(
        uid: 'user',
        paidUnlocked: true,
        testerUnlocked: false,
        businessModeActive: true,
      ).canOperateBusiness,
      isTrue,
    );
  });
}
