import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/icebreaker_service.dart';
import 'package:prox/services/matching/matching_runtime_service.dart';
import 'package:prox/services/matching/match_pipeline.dart';
import 'package:prox/services/geoquery_service.dart';
import 'package:prox/services/user_profile_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prox/widgets/icebreaker_panel.dart';

void main() {
  test(
    'Icebreaker peers cannot supply Normal matches or Treasure clues',
    () async {
      final profile = UserProfile.fromMap('alice', {
        'keywords': {
          'Searching For': ['guitar'],
          'Can Provide': ['guitar'],
        },
      });
      final runtime = MatchingRuntimeService.forTesting(
        uidProvider: () => 'alice',
        profileLoader: (_) async => profile,
      );
      NearbyDoc peer(String uid, String mode) => NearbyDoc(
        uid: uid,
        distanceMiles: 0.01,
        loc: const GeoPoint(40, -74),
        data: {
          'presence': {'modeKind': mode, 'normalMode': 'passive'},
          'keywords': {
            'Searching For': ['guitar'],
            'Can Provide': ['guitar'],
          },
        },
      );
      final peers = [peer('bob', 'icebreaker'), peer('carol', 'normal')];
      final normal = const MatchDiscoverySettings.defaults().copyWith(
        normalMode: NormalMatchMode.active,
      );
      expect(
        (await runtime.filterByModeForSettings(
          peers,
          normal,
        )).map((doc) => doc.uid),
        ['carol'],
      );
      expect(
        (await runtime.rankTreasureTargets(
          peers,
          settings: normal,
        )).map((target) => target.doc.uid),
        ['carol'],
      );
    },
  );

  test('QR parsing accepts only an explicit Icebreaker code', () {
    expect(icebreakerCodeFromQr('prox-icebreaker:012345ABCD'), '012345ABCD');
    for (final value in [
      'https://example.com',
      'prox-icebreaker:123',
      '012345ABCD',
      'prox-icebreaker:012345ABCD extra',
    ]) {
      expect(icebreakerCodeFromQr(value), isNull);
    }
  });

  test(
    'Icebreaker round-trips settings but produces no Normal candidates',
    () async {
      final settings = const MatchDiscoverySettings.defaults().copyWith(
        modeKind: MatchingModeKind.icebreaker,
      );
      expect(
        MatchDiscoverySettings.fromJson(settings.toJson()).modeKind,
        MatchingModeKind.icebreaker,
      );
      final docs = [
        NearbyDoc(
          uid: 'bob',
          distanceMiles: 0.01,
          loc: const GeoPoint(40, -74),
          data: {},
        ),
      ];
      final runtime = MatchingRuntimeService.forTesting(
        uidProvider: () => 'alice',
        profileLoader: (_) async => null,
      );
      expect(await runtime.filterByModeForSettings(docs, settings), isEmpty);
      expect(
        await MatchPipeline(
          trustScoreForUid: (_) async => throw StateError('Must not score'),
        ).buildCandidates(nearby: docs, discovery: settings),
        isEmpty,
      );
    },
  );

  testWidgets(
    'empty state offers Party, not fake matches; circle anchor remains',
    (tester) async {
      final now = DateTime(2026, 10, 11);
      final service = IcebreakerService(
        now: () => now,
        refreshLocation: () async {},
        call: (_, data) async => {
          'nearby': false,
          'signals': [],
          'band': 'none',
          'code': '012345ABCD',
          'validUntilMs': now
              .add(const Duration(seconds: 15))
              .millisecondsSinceEpoch,
          'encounter': null,
        },
      );
      await service.start('alice');
      const key = ValueKey('nearby_prox_circle_anchor');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IcebreakerView(
              service: service,
              circleKey: key,
              locationEnabled: true,
              onMode: () {},
              onConfirm: () {},
              onParty: () {},
            ),
          ),
        ),
      );
      expect(find.byKey(key), findsOneWidget);
      expect(find.textContaining('No Icebreakers nearby'), findsOneWidget);
      expect(find.text('Explore Party'), findsOneWidget);
      expect(find.text('We found each other'), findsOneWidget);
      expect(find.text('Agree to add each other to Party'), findsNothing);
      expect(
        find.text('Agree to reveal our connecting keywords'),
        findsNothing,
      );
      service.dispose();
    },
  );

  testWidgets(
    'shared signal enlarges color, symbol and mark without a profile or keyword card',
    (tester) async {
      final now = DateTime(2026, 10, 11);
      final service = IcebreakerService(
        now: () => now,
        refreshLocation: () async {},
        call: (_, data) async => {
          'nearby': true,
          'band': 'close',
          'code': '012345ABCD',
          'signals': [
            {
              'key': 'pair',
              'colorIndex': 1,
              'symbolIndex': 2,
              'mark': 'ABCD',
              'band': 'close',
            },
          ],
          'validUntilMs': now
              .add(const Duration(seconds: 15))
              .millisecondsSinceEpoch,
          'encounter': null,
        },
      );
      await service.start('alice');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IcebreakerView(
              service: service,
              circleKey: const ValueKey('nearby_prox_circle_anchor'),
              locationEnabled: true,
              onMode: () {},
              onConfirm: () {},
              onParty: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('blue bolt ABCD'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Compare color, symbol, and mark. Confirm with a code before sharing keywords.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Your connection with'), findsNothing);
      service.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
