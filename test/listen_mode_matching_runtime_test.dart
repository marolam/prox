import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/services/matching/matching_runtime_service.dart";

void main() {
  test("MatchDiscoverySettings preserves listen role from JSON", () {
    final from = MatchDiscoverySettings.fromJson(<String, dynamic>{
      "radiusMiles": 3.0,
      "modeKind": "listen",
      "listenRole": "listen",
    });

    expect(from.modeKind, MatchingModeKind.listen);
    expect(from.listenRole, ListenMatchRole.listen);

    final json = from.toJson();
    expect(json["modeKind"], "listen");
    expect(json["listenRole"], "listen");
  });

  test("Listen mode keeps only opposite-role listen peers", () async {
    final settings = const MatchDiscoverySettings.defaults().copyWith(
      modeKind: MatchingModeKind.listen,
      listenRole: ListenMatchRole.speak,
    );

    final raw = <NearbyDoc>[
      NearbyDoc(
        uid: "listen_opposite_direct",
        distanceMiles: 0.8,
        loc: const GeoPoint(0, 0),
        data: const <String, dynamic>{
          "modeKind": "listen",
          "listenRole": "listen",
        },
      ),
      NearbyDoc(
        uid: "listen_same_role",
        distanceMiles: 0.9,
        loc: const GeoPoint(0, 0),
        data: const <String, dynamic>{
          "modeKind": "listen",
          "listenRole": "speak",
        },
      ),
      NearbyDoc(
        uid: "normal_mode",
        distanceMiles: 1.0,
        loc: const GeoPoint(0, 0),
        data: const <String, dynamic>{
          "modeKind": "normal",
          "listenRole": "listen",
        },
      ),
      NearbyDoc(
        uid: "listen_opposite_nested",
        distanceMiles: 1.1,
        loc: const GeoPoint(0, 0),
        data: const <String, dynamic>{
          "matching": <String, dynamic>{
            "modeKind": "listen",
            "listenRole": "listen",
          },
        },
      ),
      NearbyDoc(
        uid: "listen_missing_role",
        distanceMiles: 1.2,
        loc: const GeoPoint(0, 0),
        data: const <String, dynamic>{
          "modeKind": "listen",
        },
      ),
    ];

    final filtered = await MatchingRuntimeService.instance
        .filterByModeForSettings(raw, settings);

    expect(
      filtered.map((d) => d.uid).toList(growable: false),
      <String>["listen_opposite_direct", "listen_opposite_nested"],
    );
  });
}
