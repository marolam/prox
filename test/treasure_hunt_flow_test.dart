import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/geoquery_service.dart';
import 'package:prox/screens/treasure_hunt/hunt_compass.dart';
import 'package:prox/services/matching/matching_runtime_service.dart';
import 'package:prox/services/matching/treasure_compass_service.dart';
import 'package:prox/services/user_profile_service.dart';

NearbyDoc peer(
  String uid, {
  String mode = 'normal',
  List<String> wants = const [],
  List<String> offers = const ['gardening'],
  double latitude = .07,
  double longitude = .07,
}) => NearbyDoc(
  uid: uid,
  distanceMiles: 5,
  loc: GeoPoint(latitude, longitude),
  data: {
    'modeKind': mode,
    'keywords': {'Searching For': wants, 'Can Provide': offers},
  },
);

void main() {
  final settings = const MatchDiscoverySettings.defaults().copyWith(
    modeKind: MatchingModeKind.treasureHunt,
    treasureRadiusMiles: 8,
  );
  MatchingRuntimeService runtime() => MatchingRuntimeService.forTesting(
    uidProvider: () => 'me',
    profileLoader: (uid) async {
      expect(
        uid,
        'me',
        reason: 'public candidate keywords must avoid extra peer reads',
      );
      return UserProfile(
        uid: uid,
        searchingFor: const ['gardening'],
        canProvide: const ['cooking'],
      );
    },
  );

  test(
    'treasure uses its own search radius but never returns normal match cards',
    () async {
      final service = runtime();
      expect(service.effectiveRadiusMiles(settings), 8);
      expect(
        await service.filterByModeForSettings([peer('peer')], settings),
        isEmpty,
      );
    },
  );

  test(
    'treasure clues honor complementary intent and exclude other mode pools',
    () async {
      final results = await runtime().rankTreasureTargets([
        peer('normal'),
        peer('hunter', mode: 'treasureHunt'),
        peer('off', mode: 'off'),
        peer('listen', mode: 'listen'),
        peer('travel', mode: 'travel'),
        peer('same-wants', wants: ['gardening'], offers: ['music']),
      ], settings: settings);
      expect(results.map((target) => target.doc.uid), ['normal', 'hunter']);
    },
  );

  test(
    'reciprocal matching criterion still applies to treasure snapshots',
    () async {
      final results = await runtime().rankTreasureTargets(
        [
          peer('one-way'),
          peer('reciprocal', wants: ['cooking']),
        ],
        settings: settings.copyWith(
          keywordMode: KeywordMatchMode.reciprocalOpposite,
          reciprocalMatchUnlocked: true,
        ),
      );
      expect(results.map((target) => target.doc.uid), ['reciprocal']);
    },
  );

  test(
    'area clusters can outweigh a single clue and retain only coarse coordinates',
    () {
      final now = DateTime(2026, 9, 13);
      final targets = [
        TreasureTarget(
          doc: peer('single', longitude: -.07),
          sharedKeywords: const ['gardening'],
        ),
        TreasureTarget(
          doc: peer('cluster1'),
          sharedKeywords: const ['gardening'],
        ),
        TreasureTarget(
          doc: peer('cluster2', latitude: .071),
          sharedKeywords: const ['gardening'],
        ),
      ];
      final snapshot = TreasureAreaSnapshot.fromTargets(
        origin: const GeoPoint(0, 0),
        targets: targets,
        now: now,
      );
      expect(snapshot.area!.longitude, greaterThan(0));
      expect(snapshot.area, isNot(targets[1].doc.loc));
      expect(snapshot.isExpired(now.add(const Duration(minutes: 4))), isFalse);
      expect(snapshot.isExpired(now.add(const Duration(minutes: 5))), isTrue);
      expect(
        TreasureAreaSnapshot.bearing(
          const GeoPoint(0, 0),
          const GeoPoint(0, 1),
        ),
        closeTo(90, .01),
      );
    },
  );

  test(
    'empty snapshot never invents a direction and warmth increases toward area',
    () {
      final snapshot = TreasureAreaSnapshot.fromTargets(
        origin: const GeoPoint(0, 0),
        targets: [],
        now: DateTime.now(),
      );
      expect(snapshot.area, isNull);
      expect([9.0, 5.0, 2.0, .5].map(TreasureAreaSnapshot.warmth), [
        'Cold',
        'Cool',
        'Warm',
        'Hot',
      ]);
    },
  );

  testWidgets(
    'compass displays coarse cardinal direction, prominent arrow and warmth',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: HuntCompass(bearingDegrees: 73, distanceMiles: 2),
            ),
          ),
        ),
      );
      expect(find.text('Head E - Warm'), findsOneWidget);
      expect(find.text('North-up compass'), findsOneWidget);
      expect(find.byIcon(Icons.navigation), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
