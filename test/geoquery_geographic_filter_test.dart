import 'dart:async';
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
    'Listen avoids profile reads for explicit non-Listen peers and follows live mode changes',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'peer', 40.001, -74.001);
      await db.doc('users/peer/presence/current').update({
        'modeKind': 'normal',
      });
      final reads = <String>[];
      // This fake's collection-group listeners do not emit document updates.
      // Feed fresh query snapshots explicitly to exercise the production stream.
      final snapshots = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      late Query<Map<String, dynamic>> query;
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => 'me',
        deviceCenterLoader: () async => null,
        locationAllowed: () async => true,
        snapshotsLoader: (value) {
          query = value;
          unawaited(query.get().then(snapshots.add));
          return snapshots.stream;
        },
        profileLoader: (uid) async {
          reads.add(uid);
          return {'displayName': uid, 'modeKind': 'normal'};
        },
      );
      final events = StreamIterator(
        service.streamNearby(
          center: const GeoPoint(40, -74),
          radiusMiles: 2,
          listenOnly: true,
        ),
      );
      expect(
        await events.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(events.current, isEmpty);
      expect(reads, isEmpty);
      await db.doc('users/peer/presence/current').update({
        'modeKind': 'listen',
      });
      snapshots.add(await query.get());
      expect(
        await events.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(events.current.single.data['presence']['modeKind'], 'listen');
      expect(reads, ['peer']);
      await db.doc('users/peer/presence/current').update({'modeKind': 'off'});
      snapshots.add(await query.get());
      expect(
        await events.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(events.current, isEmpty);
      expect(reads, ['peer']);
      await events.cancel();
      await snapshots.close();
    },
  );

  test(
    'snapshot queries finish after one bounded read and never stream peer movement',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db, 'nearby', 40.001, -74.001);
      var reads = 0;
      final service = GeoQueryService.forTesting(
        firestore: db,
        uidProvider: () => 'me',
        deviceCenterLoader: () async => null,
        locationAllowed: () async => true,
        profileLoader: (uid) async {
          reads++;
          return {'displayName': uid};
        },
      );
      final snapshots = await service
          .streamNearby(
            center: const GeoPoint(40, -74),
            radiusMiles: 10,
            snapshotOnly: true,
          )
          .toList();
      expect(snapshots.length, 1);
      expect(snapshots.single.single.uid, 'nearby');
      await seed(db, 'later-arrival', 40.002, -74.002);
      expect(reads, 1);
    },
  );

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
