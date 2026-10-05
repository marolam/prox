import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/widgets/nearby_profile_sheet.dart';

void main() {
  testWidgets(
    'profile details remain viewable independently of an expired chat',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NearbyProfileSheet(
              displayName: 'Nearby person',
              profile: {
                'bio': 'Enjoys meeting people',
                'chatGate': {'status': 'expired'},
                'presence': {'latitude': 40.123},
                'keywords': {
                  'Searching For': ['Gardening'],
                  'Can Provide': ['Cooking'],
                },
              },
            ),
          ),
        ),
      );
      expect(find.text('Nearby person'), findsOneWidget);
      expect(find.text('Enjoys meeting people'), findsOneWidget);
      expect(find.text('Gardening'), findsOneWidget);
      expect(find.text('Cooking'), findsOneWidget);
      expect(find.textContaining('expired'), findsNothing);
      expect(find.textContaining('40.123'), findsNothing);
      expect(find.text('Send new request'), findsNothing);
    },
  );
}
