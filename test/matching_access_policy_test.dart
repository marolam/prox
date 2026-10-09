import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/matching_access.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/geoquery_service.dart';
import 'package:prox/screens/services/matching/match_pipeline.dart';

void main() {
  final access = MatchingAccessSnapshot.fromMap({
    'directUids': ['friend'],
    'treeMatches': [
      {
        'uid': 'two-hops',
        'mutualUids': ['friend'],
        'mutualNames': ['Morgan'],
      },
      {
        'uid': 'distant',
        'mutualUids': ['unknown'],
        'mutualNames': ['Unknown'],
      },
    ],
  });
  const nearby = [
    NearbyDoc(uid: 'friend', distanceMiles: 2, loc: GeoPoint(0, 0), data: {}),
    NearbyDoc(uid: 'two-hops', distanceMiles: 1, loc: GeoPoint(0, 0), data: {}),
    NearbyDoc(uid: 'distant', distanceMiles: .2, loc: GeoPoint(0, 0), data: {}),
    NearbyDoc(
      uid: 'stranger',
      distanceMiles: .1,
      loc: GeoPoint(0, 0),
      data: {'partyScope': 'public', 'publicMatchingUnlocked': true},
    ),
  ];

  test('new and malformed scope settings default to Party + Tree', () {
    expect(
      const MatchDiscoverySettings.defaults().partyScope,
      MatchPartyScope.tree,
    );
    expect(
      MatchDiscoverySettings.fromJson({}).partyScope,
      MatchPartyScope.tree,
    );
    expect(
      MatchDiscoverySettings.fromJson({'partyScope': 'bad'}).partyScope,
      MatchPartyScope.tree,
    );
  });

  test(
    'tree admits direct and exact two-hop connections with known mutuals',
    () {
      expect(access.treeMatches.keys, ['two-hops']);
      expect(access.allows('friend', MatchPartyScope.partyOnly), isTrue);
      expect(access.allows('two-hops', MatchPartyScope.partyOnly), isFalse);
      expect(access.allows('two-hops', MatchPartyScope.tree), isTrue);
      expect(access.allows('distant', MatchPartyScope.tree), isFalse);
      expect(access.treeMatches['two-hops']!.label, contains('Morgan'));
    },
  );

  test('locked legacy public settings stay within the trusted tree', () {
    for (final scope in [
      MatchPartyScope.public,
      MatchPartyScope.all,
      MatchPartyScope.none,
    ]) {
      expect(access.effectiveScope(scope), MatchPartyScope.tree);
      expect(access.allows('stranger', scope), isFalse);
    }
    expect(
      MatchingAccessSnapshot.empty.allows('two-hops', MatchPartyScope.tree),
      isFalse,
    );
  });

  test('public matches require reciprocal peer access and scope', () {
    const unlocked = MatchingAccessSnapshot(
      publicUnlocked: true,
      directUids: {'friend'},
    );
    bool allows(String uid, Map<String, dynamic> peer) => unlocked.allowsPeer(
      uid: uid,
      requested: MatchPartyScope.public,
      peerProfile: peer,
    );
    expect(allows('stranger', {}), isFalse);
    expect(allows('stranger', {'partyScope': 'public'}), isFalse);
    expect(
      allows('stranger', {
        'partyScope': 'public',
        'publicMatchingUnlocked': true,
      }),
      isTrue,
    );
    expect(
      allows('stranger', {
        'partyScope': 'partyOnly',
        'publicMatchingUnlocked': true,
      }),
      isFalse,
    );
    expect(
      allows('stranger', {
        'partyScope': 'tree',
        'publicMatchingUnlocked': true,
      }),
      isFalse,
    );
    expect(allows('friend', {'partyScope': 'partyOnly'}), isTrue);
  });

  test(
    'every matching mode applies tree scope and preserves mutual identity',
    () async {
      final pipeline = MatchPipeline(trustScoreForUid: (_) async => .5);
      for (final mode in [
        MatchingModeKind.normal,
        MatchingModeKind.listen,
        MatchingModeKind.treasureHunt,
        MatchingModeKind.travel,
      ]) {
        final results = await pipeline.buildCandidates(
          nearby: nearby,
          discovery: const MatchDiscoverySettings.defaults().copyWith(
            modeKind: mode,
          ),
          matchingAccess: access,
        );
        expect(results.map((entry) => entry.uid).toSet(), {
          'friend',
          'two-hops',
        }, reason: mode.name);
        expect(
          results
              .singleWhere((entry) => entry.uid == 'two-hops')
              .profile['treeConnectionLabel'],
          contains('Morgan'),
        );
      }
    },
  );
}
