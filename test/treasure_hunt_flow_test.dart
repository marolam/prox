import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/services/geoquery_service.dart";
import "package:prox/screens/treasure_hunt/hunt_compass.dart";
import "package:prox/services/matching/matching_runtime_service.dart";
import "package:prox/services/user_settings_service.dart";

void main() {
  group("Treasure runtime behavior", () {
    setUp(() {
      UserSettingsService.instance.updateMatchDiscovery(
        const MatchDiscoverySettings.defaults(),
      );
    });

    test("effective radius uses treasure radius in treasure mode", () {
      final settings = const MatchDiscoverySettings.defaults().copyWith(
        modeKind: MatchingModeKind.treasureHunt,
        treasureRadiusMiles: 3.25,
      );

      final radius = MatchingRuntimeService.instance.effectiveRadiusMiles(settings);
      expect(radius, 3.25);
    });

    test("travel mode filters out stale presence", () async {
      UserSettingsService.instance.setMatchingMode(MatchingModeKind.travel);

      final now = DateTime.now();
      final docs = <NearbyDoc>[
        NearbyDoc(
          uid: "recent",
          loc: const GeoPoint(37.0, -122.0),
          data: <String, dynamic>{"ts": Timestamp.fromDate(now.subtract(const Duration(minutes: 2)))},
          distanceMiles: 1.0,
        ),
        NearbyDoc(
          uid: "stale",
          loc: const GeoPoint(37.1, -122.1),
          data: <String, dynamic>{"ts": Timestamp.fromDate(now.subtract(const Duration(minutes: 6)))},
          distanceMiles: 1.5,
        ),
        NearbyDoc(
          uid: "missingTs",
          loc: const GeoPoint(37.2, -122.2),
          data: const <String, dynamic>{},
          distanceMiles: 2.0,
        ),
      ];

      final filtered = await MatchingRuntimeService.instance.filterByMode(docs);
      expect(filtered.map((d) => d.uid).toList(), <String>["recent"]);
    });
  });

  testWidgets("HuntCompass renders degree label", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HuntCompass(bearingDegrees: 73),
        ),
      ),
    );

    expect(find.text("73 deg"), findsOneWidget);
    expect(find.byIcon(Icons.navigation), findsOneWidget);
    expect(find.text("Point and walk"), findsOneWidget);
  });
}
