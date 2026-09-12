import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/geoquery_service.dart';

Future<void> seed(
  FakeFirebaseFirestore db,
  String uid,
  double lat,
  double lon,
) async {
  await db.doc('users/$uid/presence/current').set({
    'kind': 'current',
    'geopoint': GeoPoint(lat, lon),
    'latitude': lat,
    'longitude': lon,
    'ts': Timestamp.now(),
    'expiresAt': Timestamp.fromDate(
      DateTime.now().add(const Duration(minutes: 2)),
    ),
  });
  await db.doc('publicProfiles/$uid').set({'displayName': uid});
}

void main() {
  test(
    'distant users cannot fill the limit before local people are selected',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 60; i++) {
        await seed(db, 'distant-$i', -60, -100);
      }
      await seed(db, 'nearby', 40.001, -74.001);
      final profileReads = <String>[];
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => 'me',
        deviceCenterLoader: () async => null,
        locationAllowed: () async => true,
        profileLoader: (uid) async {
          profileReads.add(uid);
          return {'displayName': uid};
        },
      );
      final rows = await service
          .streamNearby(
            center: const GeoPoint(40, -74),
            radiusMiles: 10,
            limitUsers: 1,
          )
          .first;
      expect(rows.map((row) => row.uid), ['nearby']);
      expect(profileReads, ['nearby']);
      expect(service.debug.cgTotal, 1);
    },
  );

  test('one geographic query returns both sides of the date line', () async {
    final db = FakeFirebaseFirestore();
    await seed(db, 'east', 0, 179.98);
    await seed(db, 'west', 0, -179.98);
    await seed(db, 'far', 0, 0);
    final service = GeoQueryService.forTesting(
      firestore: db,
      uidProvider: () => 'me',
      deviceCenterLoader: () async => null,
      locationAllowed: () async => true,
    );
    final rows = await service
        .streamNearby(center: const GeoPoint(0, 179.99), radiusMiles: 5)
        .first;
    expect(rows.map((row) => row.uid), ['east', 'west']);
    expect(service.debug.cgTotal, 2);
  });

  test(
    'bounding-box corner candidates outside the circle never load profiles',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'corner', 0.13, 0.13);
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => 'me',
        deviceCenterLoader: () async => null,
        locationAllowed: () async => true,
        profileLoader: (_) async =>
            throw StateError('Outside-radius profile read'),
      );
      final rows = await service
          .streamNearby(center: const GeoPoint(0, 0), radiusMiles: 10)
          .first;
      expect(rows, isEmpty);
      expect(service.debug.cgTotal, 1);
    },
  );
}
