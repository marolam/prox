import 'dart:math' as math;

class LongitudeRange {
  const LongitudeRange(this.west, this.east);
  final double west;
  final double east;
}

/// Spherical bounds enclosing a radius. A date-line crossing has two longitude
/// intervals; a radius touching a pole includes every longitude.
class GeoQueryBounds {
  const GeoQueryBounds({
    required this.south,
    required this.north,
    required this.longitudes,
  });
  final double south;
  final double north;
  final List<LongitudeRange> longitudes;

  factory GeoQueryBounds.around({
    required double latitude,
    required double longitude,
    required double radiusMiles,
  }) {
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        !radiusMiles.isFinite ||
        radiusMiles <= 0) {
      throw ArgumentError(
        'Valid coordinates and a positive finite radius are required.',
      );
    }
    const earthRadiusMiles = 3958.8;
    const radians = math.pi / 180;
    final angular = math.min(math.pi, radiusMiles / earthRadiusMiles);
    final lat = latitude * radians;
    final south = math.max(-math.pi / 2, lat - angular) / radians;
    final north = math.min(math.pi / 2, lat + angular) / radians;
    if (south <= -90 || north >= 90) {
      return GeoQueryBounds(
        south: south,
        north: north,
        longitudes: const [LongitudeRange(-180, 180)],
      );
    }
    final delta =
        math.asin((math.sin(angular) / math.cos(lat)).clamp(-1.0, 1.0)) /
        radians;
    final west = longitude - delta;
    final east = longitude + delta;
    final ranges = west < -180
        ? [LongitudeRange(-180, east), LongitudeRange(west + 360, 180)]
        : east > 180
        ? [LongitudeRange(west, 180), LongitudeRange(-180, east - 360)]
        : [LongitudeRange(west, east)];
    return GeoQueryBounds(south: south, north: north, longitudes: ranges);
  }
}
