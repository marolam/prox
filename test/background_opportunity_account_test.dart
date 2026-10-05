import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/background_opportunity_service.dart';
import 'package:prox/screens/matches/background_matches_screen.dart';
import 'package:prox/screens/matches/significant_match_screen.dart';

void main() {
  test(
    'background reads send the bound UID and discard a delayed old response',
    () async {
      String? uid = 'account-a';
      final response = Completer<Map<String, dynamic>>();
      final service = BackgroundOpportunityService(
        currentUid: () => uid,
        accountChanges: () => const Stream.empty(),
        invoke: (name, data) {
          expect(name, 'getBackgroundOpportunity');
          expect(data['expectedUid'], 'account-a');
          return response.future;
        },
      );
      final read = service.get('account-a', 'opportunity');
      final check = expectLater(read, throwsA(isA<BackgroundAccountChanged>()));
      uid = 'account-b';
      response.complete({
        'available': true,
        'displayName': 'Private account A peer',
      });
      await check;
    },
  );

  test(
    'a stale view cannot begin a background read with the new account',
    () async {
      var calls = 0;
      final service = BackgroundOpportunityService(
        currentUid: () => 'account-b',
        accountChanges: () => const Stream.empty(),
        invoke: (_, __) async {
          calls++;
          return {'opportunities': []};
        },
      );
      await expectLater(
        service.list('account-a'),
        throwsA(isA<BackgroundAccountChanged>()),
      );
      expect(calls, 0);
    },
  );

  testWidgets('background list clears cached peer details on account change', (
    tester,
  ) async {
    String? uid = 'account-a';
    final accounts = StreamController<String?>.broadcast();
    addTearDown(accounts.close);
    final service = BackgroundOpportunityService(
      currentUid: () => uid,
      accountChanges: () => accounts.stream,
      invoke: (_, __) async => {
        'opportunities': [
          {
            'displayName': 'Private account A peer',
            'opportunityId': 'opportunity',
            'significant': true,
          },
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: BackgroundMatchesScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private account A peer'), findsOneWidget);
    uid = 'account-b';
    accounts.add(uid);
    await tester.pumpAndSettle();
    expect(find.text('Private account A peer'), findsNothing);
    expect(find.text('Return to Nearby to continue.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a delayed background detail cannot render after sign out', (
    tester,
  ) async {
    String? uid = 'account-a';
    final accounts = StreamController<String?>.broadcast();
    final response = Completer<Map<String, dynamic>>();
    addTearDown(accounts.close);
    final service = BackgroundOpportunityService(
      currentUid: () => uid,
      accountChanges: () => accounts.stream,
      invoke: (_, __) => response.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SignificantMatchScreen(
          opportunityId: 'opportunity',
          service: service,
        ),
      ),
    );
    await tester.pump();
    uid = null;
    accounts.add(uid);
    await tester.pump();
    response.complete({
      'available': true,
      'displayName': 'Private account A peer',
      'forYou': ['private interest'],
    });
    await tester.pumpAndSettle();
    expect(find.text('Private account A peer'), findsNothing);
    expect(find.text('private interest'), findsNothing);
    expect(find.text('Return to Nearby to continue.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
