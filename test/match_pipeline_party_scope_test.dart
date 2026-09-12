import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter_test/flutter_test.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/screens/services/matching/match_pipeline.dart";

void main() {
  test("filters out non-party members when party scope is active", () async {
    final candidates = <NearbyDoc>[
      NearbyDoc(
        uid: "member",
        distanceMiles: 0.7,
        loc: const GeoPoint(0, 0),
        data: <String, dynamic>{},
      ),
      NearbyDoc(
        uid: "stranger",
        distanceMiles: 0.4,
        loc: const GeoPoint(0, 0),
        data: <String, dynamic>{},
      ),
    ];

    final lookedUp = <String>[];
    final pipeline = MatchPipeline(trustScoreForUid: (uid) async {
      lookedUp.add(uid);
      return 0.5;
    });
    final result = await pipeline.buildCandidates(
      nearby: candidates,
      myPartyId: "",
      discovery: const MatchDiscoverySettings.defaults().copyWith(
        partyScope: MatchPartyScope.partyOnly,
      ),
      partyMemberUids: const <String>{"member"},
    );

    expect(result.map((c) => c.uid).toList(growable: false), ["member"]);
    expect(lookedUp, ["member"], reason: "Never fetch private-scoped strangers' profiles");
  });

  test("does not filter when scope is public", () async {
    final candidates = <NearbyDoc>[
      NearbyDoc(
        uid: "member",
        distanceMiles: 0.7,
        loc: const GeoPoint(0, 0),
        data: <String, dynamic>{},
      ),
      NearbyDoc(
        uid: "stranger",
        distanceMiles: 0.4,
        loc: const GeoPoint(0, 0),
        data: <String, dynamic>{},
      ),
    ];

    final result = await MatchPipeline(trustScoreForUid: (_) async => 0.5).buildCandidates(
      nearby: candidates,
      myPartyId: "",
      discovery: const MatchDiscoverySettings.defaults().copyWith(
        partyScope: MatchPartyScope.public,
      ),
    );

    final ids = result.map((c) => c.uid).toSet();
    expect(ids, contains("member"));
    expect(ids, contains("stranger"));
  });
}
