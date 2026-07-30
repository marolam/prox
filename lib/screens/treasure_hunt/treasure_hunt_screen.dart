import "dart:math";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/services/matching/matching_mode_service.dart";
import "package:prox/services/matching/matching_runtime_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/utils/presentation/prox_distance_format.dart";

import "hunt_compass.dart";

class TreasureHuntScreen extends StatelessWidget {
  const TreasureHuntScreen({super.key});

  static GeoPoint? _extractGeo(Map<String, dynamic> d) {
    final gp = d["geopoint"];
    if (gp is GeoPoint) return gp;
    final lat = d["lat"];
    final lon = d["lon"];
    if (lat is num && lon is num) return GeoPoint(lat.toDouble(), lon.toDouble());
    return null;
  }

  static double _bearingDegrees(GeoPoint from, GeoPoint to) {
    final lat1 = from.latitude * pi / 180.0;
    final lat2 = to.latitude * pi / 180.0;
    final dLon = (to.longitude - from.longitude) * pi / 180.0;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final deg = atan2(y, x) * 180.0 / pi;
    return (deg + 360.0) % 360.0;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final cs = Theme.of(context).colorScheme;

    if (uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Treasure Hunt")),
        body: const Center(child: Text("Sign in to use Treasure Hunt.")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Treasure Hunt")),
      body: StreamBuilder<UserSettings>(
        stream: UserSettingsService.instance.watch(),
        builder: (context, ssnap) {
          final settings = ssnap.data ?? UserSettingsService.instance.current;
          final discovery = settings.matchDiscovery;
          final radius = MatchingRuntimeService.instance.effectiveRadiusMiles(discovery);

          if (discovery.modeKind != MatchingModeKind.treasureHunt) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Set matching mode to Treasure Hunt to see compass targets."),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        MatchingModeService.instance.setModeKind(MatchingModeKind.treasureHunt);
                      },
                      child: const Text("Switch to Treasure Hunt"),
                    ),
                  ],
                ),
              ),
            );
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.doc("users/$uid/presence/current").snapshots(),
            builder: (context, centerSnap) {
              final centerData = centerSnap.data?.data() ?? const <String, dynamic>{};
              final center = _extractGeo(centerData);

              return StreamBuilder<List<NearbyDoc>>(
                stream: GeoQueryService.instance.streamNearby(
                  center: null,
                  radiusMiles: radius,
                ),
                builder: (context, nearbySnap) {
                  final raw = nearbySnap.data ?? const <NearbyDoc>[];

                  return FutureBuilder<List<TreasureTarget>>(
                    future: MatchingRuntimeService.instance
                        .rankTreasureTargets(raw)
                        .timeout(const Duration(seconds: 8), onTimeout: () => const <TreasureTarget>[]),
                    builder: (context, targetSnap) {
                      final targets = targetSnap.data ?? const <TreasureTarget>[];

                      if (targetSnap.connectionState == ConnectionState.waiting && targets.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.explore_outlined, size: 42, color: cs.primary),
                                const SizedBox(height: 10),
                                Text(
                                  "Finding nearby clues...",
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Compass will appear when targets are ready.",
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (targets.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "No keyword matches nearby yet. Expand radius or add clearer profile keywords.",
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "Current radius: ${radius.toStringAsFixed(1)} mi",
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "If this persists, open Nearby for 10-20 seconds, then return to Compass.",
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final top = targets.first;
                      final bearing = center == null ? null : _bearingDegrees(center, top.doc.loc);
                      final topKeyword = top.sharedKeywords.first;

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                        children: [
                          Text(
                            "Hot target",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            topKeyword,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 14),
                          HuntCompass(bearingDegrees: bearing ?? 0),
                          const SizedBox(height: 10),
                          Text(
                            bearing == null
                                ? "Waiting for your live location to calculate direction."
                                : "Bearing ${bearing.toStringAsFixed(0)} deg",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            "Top nearby clues",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          for (final t in targets.take(6)) ...[
                            Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: ListTile(
                                leading: const Icon(Icons.explore_outlined),
                                title: Text(t.sharedKeywords.join(", "), maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  ProxDistanceFormat.bucketMilesOrNull(t.doc.distanceMiles) ??
                                      "${t.doc.distanceMiles.toStringAsFixed(1)} mi",
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}




