import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/geoquery_service.dart';

Future<void> seedPresence(FakeFirebaseFirestore db, String uid) =>
    db.doc('users/$uid/presence/current').set({
      'kind': 'current',
      'geopoint': const GeoPoint(0, 0),
      'latitude': 0.0,
      'longitude': 0.0,
      'ts': Timestamp.now(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(minutes: 2)),
      ),
    });

void main() {
  test(
    'discovery uses sanitized public profiles and skips unpublished peers',
    () async {
      final db = FakeFirebaseFirestore();
      await seedPresence(db, 'published');
      await seedPresence(db, 'private-only');
      await db.doc('users/published').set({'email': 'private@example.com'});
      await db.doc('users/private-only').set({'displayName': 'Private'});
      await db.doc('publicProfiles/published').set({
        'displayName': 'Published',
      });
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => 'me',
        deviceCenterLoader: () async => null,
        locationAllowed: () async => true,
      );
      final rows = await service
          .streamNearby(center: const GeoPoint(0, 0), radiusMiles: 10)
          .first;
      expect(rows.map((row) => row.uid), ['published']);
      expect(rows.single.data['displayName'], 'Published');
      expect(rows.single.data.containsKey('email'), isFalse);
    },
  );

  test(
    'incomplete cached centers require a fresh permitted device location',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/me/presence/current').set({
        'geopoint': const GeoPoint(30, 40),
      });
      var deviceReads = 0;
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => 'me',
        deviceCenterLoader: () async {
          deviceReads++;
          return const GeoPoint(0, 0);
        },
        locationAllowed: () async => true,
      );
      expect(
        await service.streamNearby(center: null, radiusMiles: 10).first,
        isEmpty,
      );
      expect(deviceReads, 1);
      expect(service.debug.centerLabel, contains('0.00000,0.00000 (device)'));
    },
  );

  test(
    'account change during a device lookup discards the previous center',
    () async {
      final db = FakeFirebaseFirestore();
      String? uid = 'account-a';
      final pending = Completer<GeoPoint?>();
      final requested = Completer<void>();
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => uid,
        deviceCenterLoader: () {
          requested.complete();
          return pending.future;
        },
        locationAllowed: () async => true,
      );
      final result = service.streamNearby(center: null, radiusMiles: 10).first;
      await requested.future;
      uid = 'account-b';
      pending.complete(const GeoPoint(0, 0));
      expect(await result, isEmpty);
      expect(service.debug.centerKnown, isFalse);
    },
  );

  test('opt-out prevents any discovery location lookup', () async {
    final service = GeoQueryService.forTesting(
      firestore: FakeFirebaseFirestore(),
      uidProvider: () => 'me',
      deviceCenterLoader: () async => throw StateError('GPS must stay off'),
      locationAllowed: () async => false,
    );
    expect(
      await service.streamNearby(center: null, radiusMiles: 10).first,
      isEmpty,
    );
  });

  test(
    'session cleanup during a peer profile read discards pending rows',
    () async {
      final db = FakeFirebaseFirestore();
      await seedPresence(db, 'peer');
      final pending = Completer<Map<String, dynamic>?>();
      final requested = Completer<void>();
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => 'me',
        deviceCenterLoader: () async => null,
        locationAllowed: () async => true,
        profileLoader: (_) {
          requested.complete();
          return pending.future;
        },
      );
      final result = service
          .streamNearby(center: const GeoPoint(0, 0), radiusMiles: 10)
          .first;
      await requested.future;
      service.clearSession();
      pending.complete({'displayName': 'Old session peer'});
      expect(await result, isEmpty);
      expect(service.debug.centerKnown, isFalse);
    },
  );
}
