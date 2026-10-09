import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/widgets/party_referral_consent.dart';

void main() {
  for (final accept in [false, true]) {
    testWidgets(
      'QR Party joining requires an explicit ${accept ? 'acceptance' : 'decline'}',
      (tester) async {
        bool? decision;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async =>
                      decision = await showPartyReferralConsent(context),
                  child: const Text('Open invite'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open invite'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Accept only if you are together'),
          findsOneWidget,
        );
        expect(decision, isNull);
        await tester.tap(
          find.text(
            accept ? 'We’ve met — join Party' : 'Continue without joining',
          ),
        );
        await tester.pumpAndSettle();
        expect(decision, accept);
      },
    );
  }
}
