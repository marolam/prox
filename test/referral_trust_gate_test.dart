import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/widgets/referral_trust_gate.dart';

void main() {
  testWidgets(
    'new accounts stay gated until server-owned in-person verification, while legacy accounts remain eligible',
    (tester) async {
      final account = StreamController<Map<String, dynamic>?>();
      addTearDown(account.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ReferralTrustGate(
            uid: 'newbie',
            accountStream: account.stream,
            child: const Text('Matching ready'),
          ),
        ),
      );
      account.add({
        'referralTrustRequired': true,
        'referralInPersonVerified': false,
      });
      await tester.pumpAndSettle();
      expect(find.text('Matching ready'), findsNothing);
      expect(find.text('Contact support'), findsOneWidget);
      account.add({
        'referralTrustRequired': true,
        'referralInPersonVerified': true,
      });
      await tester.pumpAndSettle();
      expect(find.text('Matching ready'), findsOneWidget);
      account.add({});
      await tester.pumpAndSettle();
      expect(find.text('Matching ready'), findsOneWidget);
    },
  );

  testWidgets(
    'suspension and stream errors never reveal a previously unlocked home',
    (tester) async {
      final account = StreamController<Map<String, dynamic>?>();
      addTearDown(account.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ReferralTrustGate(
            uid: 'user',
            accountStream: account.stream,
            child: const Text('Matching ready'),
          ),
        ),
      );
      account.add({});
      await tester.pumpAndSettle();
      account.add({'disabled': true});
      await tester.pumpAndSettle();
      expect(find.text('Matching ready'), findsNothing);
      expect(find.text('Account restricted'), findsOneWidget);
      account.add({});
      await tester.pumpAndSettle();
      account.addError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      expect(find.text('Matching ready'), findsNothing);
      expect(
        find.textContaining('Could not verify account access'),
        findsOneWidget,
      );
    },
  );
}
