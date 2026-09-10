import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prox/utils/geo_query_bounds.dart';

void main() {
  test(
    'ordinary radius bounds contain every heading at the search boundary',
    () {
      for (final location in [
        (40.7, -74.0),
        (-35.0, 149.0),
        (70.0, 30.0),
        (0.0, 179.99),
      ]) {
        final bounds = GeoQueryBounds.around(
          latitude: location.$1,
          longitude: location.$2,
          radiusMiles: 30,
        );
        final lat = location.$1 * math.pi / 180;
        final lon = location.$2 * math.pi / 180;
        const angle = 29.999 / 3958.8;
        for (var heading = 0; heading < 360; heading += 5) {
          final bearing = heading * math.pi / 180;
          final endLat = math.asin(
            math.sin(lat) * math.cos(angle) +
                math.cos(lat) * math.sin(angle) * math.cos(bearing),
          );
          final endLon =
              lon +
              math.atan2(
                math.sin(bearing) * math.sin(angle) * math.cos(lat),
                math.cos(angle) - math.sin(lat) * math.sin(endLat),
              );
          final latitude = endLat * 180 / math.pi;
          final longitude = (endLon * 180 / math.pi + 540) % 360 - 180;
          expect(latitude, inInclusiveRange(bounds.south, bounds.north));
          expect(
            bounds.longitudes.any(
              (range) => longitude >= range.west && longitude <= range.east,
            ),
            isTrue,
            reason: '$location, heading $heading',
          );
        }
      }
    },
  );

  test(
    'both date-line crossing directions split into valid longitude intervals',
    () {
      for (final lon in [-179.99, 179.99]) {
        final bounds = GeoQueryBounds.around(
          latitude: 0,
          longitude: lon,
          radiusMiles: 10,
        );
        expect(bounds.longitudes.length, 2);
        for (final range in bounds.longitudes) {
          expect(range.west, greaterThanOrEqualTo(-180));
          expect(range.east, lessThanOrEqualTo(180));
          expect(range.west, lessThan(range.east));
        }
      }
    },
  );

  test(
    'pole-reaching searches include every longitude and invalid input fails',
    () {
      final bounds = GeoQueryBounds.around(
        latitude: 89.9,
        longitude: 20,
        radiusMiles: 20,
      );
      expect(bounds.north, 90);
      expect(bounds.longitudes.single.west, -180);
      expect(bounds.longitudes.single.east, 180);
      expect(
        () => GeoQueryBounds.around(
          latitude: 0,
          longitude: 0,
          radiusMiles: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () =>
            GeoQueryBounds.around(latitude: 91, longitude: 0, radiusMiles: 10),
        throwsArgumentError,
      );
    },
  );
}
