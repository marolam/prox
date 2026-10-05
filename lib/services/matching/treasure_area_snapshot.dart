import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prox/services/matching/matching_runtime_service.dart';

class TreasureAreaSnapshot {
  const TreasureAreaSnapshot({
    required this.origin,
    required this.area,
    required this.capturedAt,
  });

  final GeoPoint origin;
  // Only a coarse area center is retained, never an individual target/profile.
  final GeoPoint? area;
  final DateTime capturedAt;
  static const lifetime = Duration(minutes: 5);

  bool isExpired(DateTime now) => now.difference(capturedAt) >= lifetime;

  static double distanceMiles(GeoPoint from, GeoPoint to) {
    const radians = math.pi / 180;
    final lat = (to.latitude - from.latitude) * radians;
    final lon = (to.longitude - from.longitude) * radians;
    final h =
        math.pow(math.sin(lat / 2), 2) +
        math.cos(from.latitude * radians) *
            math.cos(to.latitude * radians) *
            math.pow(math.sin(lon / 2), 2);
    return 7917.6 * math.asin(math.sqrt(h.clamp(0, 1)));
  }

  static double bearing(GeoPoint from, GeoPoint to) {
    const radians = math.pi / 180;
    final delta = (to.longitude - from.longitude) * radians;
    final y = math.sin(delta) * math.cos(to.latitude * radians);
    final x =
        math.cos(from.latitude * radians) * math.sin(to.latitude * radians) -
        math.sin(from.latitude * radians) *
            math.cos(to.latitude * radians) *
            math.cos(delta);
    return (math.atan2(y, x) / radians + 360) % 360;
  }

  static String warmth(double miles) => miles <= 1
      ? 'Hot'
      : miles <= 3
      ? 'Warm'
      : miles <= 6
      ? 'Cool'
      : 'Cold';

  static double heat(double miles) => switch (warmth(miles)) {
    'Hot' => 1,
    'Warm' => .7,
    'Cool' => .4,
    _ => .15,
  };

  static TreasureAreaSnapshot fromTargets({
    required GeoPoint origin,
    required List<TreasureTarget> targets,
    required DateTime now,
  }) {
    // Roughly one-mile cells. Weight clusters by compatible keywords and
    // proximity; do not point at the exact location of a single person.
    const latStep = 1 / 69.0;
    final lonStep =
        latStep / math.max(.01, math.cos(origin.latitude * math.pi / 180));
    final weights = <(int, int), double>{};
    for (final target in targets) {
      final key = (
        (target.doc.loc.latitude / latStep).floor(),
        ((target.doc.loc.longitude + 180) / lonStep).floor(),
      );
      weights[key] =
          (weights[key] ?? 0) +
          (1 + math.min(3, target.sharedKeywords.length)) /
              (1 + target.doc.distanceMiles / 5);
    }
    final areas = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = areas.isEmpty ? null : areas.first.key;
    return TreasureAreaSnapshot(
      origin: origin,
      area: best == null
          ? null
          : GeoPoint(
              ((best.$1 + .5) * latStep).clamp(-90, 90),
              ((best.$2 + .5) * lonStep - 180).clamp(-180, 180),
            ),
      capturedAt: now,
    );
  }
}
