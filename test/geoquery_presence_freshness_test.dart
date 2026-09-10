import "package:flutter_test/flutter_test.dart";

import "package:prox/services/geoquery_service.dart";

void main() {
  group("Nearby presence freshness", () {
    final now = DateTime.utc(2026, 8, 27, 10);

    test("accepts a current unexpired presence", () {
      expect(
        GeoQueryService.isPresenceLive(
          timestamp: now.subtract(const Duration(seconds: 45)),
          expiresAt: now.add(const Duration(minutes: 2)),
          now: now,
        ),
        isTrue,
      );
    });

    test("rejects stale, expired, and incomplete presence", () {
      expect(
        GeoQueryService.isPresenceLive(
          timestamp: now.subtract(const Duration(minutes: 4)),
          expiresAt: now.add(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(
        GeoQueryService.isPresenceLive(
          timestamp: now.subtract(const Duration(seconds: 30)),
          expiresAt: now,
          now: now,
        ),
        isFalse,
      );
      expect(
        GeoQueryService.isPresenceLive(
          timestamp: null,
          expiresAt: now.add(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
