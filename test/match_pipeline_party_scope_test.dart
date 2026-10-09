import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter_test/flutter_test.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/models/matching_access.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/screens/services/matching/match_pipeline.dart";

void main() {
  test(
    'Listen cards do not wait for trust reads or boost Party membership',
    () async {
      final pipeline = MatchPipeline(
        trustScoreForUid: (_) =>
            throw StateError('Listen must not fetch trust'),
      );
      final result = await pipeline.buildCandidates(
        nearby: const [
          NearbyDoc(
            uid: 'party-far',
            distanceMiles: 2,
            loc: GeoPoint(0, 0),
            data: {'partyId': 'my-party'},
          ),
          NearbyDoc(
            uid: 'near',
            distanceMiles: .1,
            loc: GeoPoint(0, 0),
            data: {},
          ),
        ],
        myPartyId: 'my-party',
        partyMemberUids: const {'party-far'},
        discovery: const MatchDiscoverySettings.defaults().copyWith(
          modeKind: MatchingModeKind.listen,
          partyScope: MatchPartyScope.partyOnly,
        ),
      );
      expect(result.map((candidate) => candidate.uid), ['party-far']);
      expect(result.every((candidate) => !candidate.sameParty), isTrue);
    },
  );

  test("filters out non-party members when party scope is active", () async {
    final candidates = <NearbyDoc>[
      NearbyDoc(
        uid: "member",
        distanceMiles: 0.7,
        loc: const GeoPoint(0, 0),
        data: <String, dynamic>{
          'partyScope': 'public',
          'publicMatchingUnlocked': true,
        },
      ),
      NearbyDoc(
        uid: "stranger",
        distanceMiles: 0.4,
        loc: const GeoPoint(0, 0),
        data: <String, dynamic>{
          'partyScope': 'public',
          'publicMatchingUnlocked': true,
        },
      ),
    ];

    final lookedUp = <String>[];
    final pipeline = MatchPipeline(
      trustScoreForUid: (uid) async {
        lookedUp.add(uid);
        return 0.5;
      },
    );
    final result = await pipeline.buildCandidates(
      nearby: candidates,
      myPartyId: "",
      discovery: const MatchDiscoverySettings.defaults().copyWith(
        partyScope: MatchPartyScope.partyOnly,
      ),
      partyMemberUids: const <String>{"member"},
    );

    expect(result.map((c) => c.uid).toList(growable: false), ["member"]);
    expect(lookedUp, [
      "member",
    ], reason: "Never fetch private-scoped strangers' profiles");
  });

  test("unlocked public admits peers who also allow public matching", () async {
    final candidates = <NearbyDoc>[
      NearbyDoc(
        uid: "member",
        distanceMiles: 0.7,
        loc: const GeoPoint(0, 0),
        data: <String, dynamic>{
          'partyScope': 'public',
          'publicMatchingUnlocked': true,
        },
      ),
      NearbyDoc(
        uid: "stranger",
        distanceMiles: 0.4,
        loc: const GeoPoint(0, 0),
        data: <String, dynamic>{
          'partyScope': 'public',
          'publicMatchingUnlocked': true,
        },
      ),
    ];

    final result = await MatchPipeline(trustScoreForUid: (_) async => 0.5)
        .buildCandidates(
          nearby: candidates,
          myPartyId: "",
          discovery: const MatchDiscoverySettings.defaults().copyWith(
            partyScope: MatchPartyScope.public,
          ),
          matchingAccess: const MatchingAccessSnapshot(publicUnlocked: true),
        );

    final ids = result.map((c) => c.uid).toSet();
    expect(ids, contains("member"));
    expect(ids, contains("stranger"));
  });
}
