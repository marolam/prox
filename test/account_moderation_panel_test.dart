import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/widgets/account_moderation_panel.dart';

void main() {
  testWidgets(
    'suspension needs confirmation; failed actions retain the same request ID',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AccountModerationPanel(
            ownerUid: 'admin',
            call: (payload) async {
              requests.add(payload);
              if (requests.length == 1)
                throw StateError('temporary service failure');
              return {'status': 'suspended'};
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), 'target');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Reported referral farming',
      );
      await tester.tap(find.text('Review action'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Retry same action'), findsOneWidget);
      await tester.tap(find.text('Retry same action'));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(requests[0], requests[1]);
      expect(find.text('Verified: target is suspended.'), findsOneWidget);
    },
  );
}
