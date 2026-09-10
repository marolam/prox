import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/geoquery_service.dart';

void main() {
  test(
    'a missing location is distinct from a successful empty search',
    () async {
      final service = GeoQueryService.forTesting(
        firestore: FakeFirebaseFirestore(),
        uidProvider: () => 'me',
        deviceCenterLoader: () async => null,
        locationAllowed: () async => true,
      );
      expect(
        await service.streamNearby(center: null, radiusMiles: 10).first,
        isEmpty,
      );
      expect(service.debug.status, GeoQueryStatus.locationUnavailable);
      expect(service.debug.centerKnown, isFalse);
      expect(service.debug.lastError, isNot(contains('/users/')));
    },
  );

  test(
    'a new subscription recovers after an initial location failure',
    () async {
      final requested = Completer<void>();
      final pending = Completer<GeoPoint?>();
      var attempts = 0;
      final service = GeoQueryService.forTesting(
        firestore: FakeFirebaseFirestore(),
        uidProvider: () => 'me',
        deviceCenterLoader: () async {
          if (attempts++ == 0) return null;
          requested.complete();
          return pending.future;
        },
        locationAllowed: () async => true,
      );
      await service.streamNearby(center: null, radiusMiles: 10).first;
      expect(service.debug.status, GeoQueryStatus.locationUnavailable);
      final retry = service.streamNearby(center: null, radiusMiles: 10).first;
      await requested.future;
      expect(service.debug.status, GeoQueryStatus.loading);
      pending.complete(const GeoPoint(0, 0));
      expect(await retry, isEmpty);
      expect(service.debug.status, GeoQueryStatus.ready);
      expect(service.debug.centerKnown, isTrue);
      expect(service.debug.lastError, isEmpty);
    },
  );

  test('location opt-out does not look like an empty search', () async {
    final service = GeoQueryService.forTesting(
      firestore: FakeFirebaseFirestore(),
      uidProvider: () => 'me',
      deviceCenterLoader: () async => throw StateError('GPS must stay off'),
      locationAllowed: () async => false,
    );
    await service.streamNearby(center: null, radiusMiles: 10).first;
    expect(service.debug.status, GeoQueryStatus.locationOff);
  });

  test(
    'failed peer reads are skipped without breaking nearby results',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/peer/presence/current').set({
        'kind': 'current',
        'geopoint': const GeoPoint(0, 0),
        'latitude': 0.0,
        'longitude': 0.0,
        'ts': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 2)),
        ),
      });
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => 'me',
        deviceCenterLoader: () async => null,
        locationAllowed: () async => true,
        profileLoader: (_) async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      );
      final result =
          await service
              .streamNearby(center: const GeoPoint(0, 0), radiusMiles: 10)
              .first;
      expect(result, isEmpty);
      expect(service.debug.status, GeoQueryStatus.ready);
    },
  );
}
