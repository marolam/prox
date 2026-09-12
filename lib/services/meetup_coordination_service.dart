import "dart:math" as math;

import "package:geolocator/geolocator.dart";

class MeetupCoordinationInfo {
  const MeetupCoordinationInfo({
    required this.distanceMeters,
    required this.bearingDegrees,
    required this.cardinalDirection,
    required this.roughWalkingMinutes,
  });

  final double distanceMeters;
  final double bearingDegrees;
  final String cardinalDirection;
  final int roughWalkingMinutes;

  String get distanceLabel {
    if (distanceMeters < 1000) return "${distanceMeters.round()} m";
    return "${(distanceMeters / 1000).toStringAsFixed(1)} km";
  }

  static MeetupCoordinationInfo between({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    final distance = Geolocator.distanceBetween(
      fromLat,
      fromLng,
      toLat,
      toLng,
    );
    final lat1 = fromLat * math.pi / 180;
    final lat2 = toLat * math.pi / 180;
    final deltaLng = (toLng - fromLng) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    final bearing = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    const directions = <String>["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    final direction = directions[((bearing + 22.5) ~/ 45) % 8];
    final walkMinutes = math.max(1, (distance / 1.4 / 60).ceil());

    return MeetupCoordinationInfo(
      distanceMeters: distance,
      bearingDegrees: bearing,
      cardinalDirection: direction,
      roughWalkingMinutes: walkMinutes,
    );
  }
}
