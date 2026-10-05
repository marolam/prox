import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/party_mode_service.dart';

void main() {
  test(
    'one-shot treasure membership loads approved peers without using the reset event',
    () async {
      final db = FakeFirebaseFirestore();
      final party = db.collection('users').doc('alice').collection('party');
      await party.doc('approved').set({'mutual': true});
      await party.doc('pending').set({'mutual': false});
      await party.doc('legacy').set({'partyId': 'old-group'});
      await party.doc('current').set({'mutual': true});
      await party.doc('partySettings').set({'mutual': true});
      await party.doc('alice').set({'mutual': true});
      await db
          .collection('users')
          .doc('bob')
          .collection('party')
          .doc('bob-peer')
          .set({'mutual': true});
      final service = PartyModeService(
        firestore: db,
        currentUid: () => 'alice',
        accountChanges: () => const Stream<String?>.empty(),
      );

      // The live API deliberately starts with an empty reset. A one-shot compass
      // load must wait for Firestore instead and retain the approved Party scope.
      expect(await service.watchApprovedPartyUids().first, isEmpty);
      final members = await service.loadApprovedPartyUids('alice');
      expect(members, {'approved'});
      expect(() => members.add('injected'), throwsUnsupportedError);
    },
  );

  test(
    'a genuinely empty loaded Party snapshot completes without waiting for a peer',
    () async {
      final service = PartyModeService(
        firestore: FakeFirebaseFirestore(),
        currentUid: () => 'alice',
      );
      expect(await service.loadApprovedPartyUids('alice'), isEmpty);
    },
  );

  test(
    'an account switch rejects a delayed approved-member snapshot',
    () async {
      final pending = Completer<Set<String>>();
      String? uid = 'alice';
      var reads = 0;
      final service = PartyModeService(
        currentUid: () => uid,
        approvedMembers: (owner) {
          expect(owner, 'alice');
          reads++;
          return Stream.fromFuture(pending.future);
        },
      );
      final load = service.loadApprovedPartyUids('alice');
      final rejected = expectLater(load, throwsStateError);
      uid = 'bob';
      pending.complete({'alice-private-peer'});
      await rejected;
      expect(reads, 1);
      await expectLater(
        service.loadApprovedPartyUids('alice'),
        throwsStateError,
      );
      expect(reads, 1, reason: 'Stale account requests must not start a read.');
    },
  );

  test('sign-out rejects an in-flight one-shot snapshot', () async {
    final pending = Completer<Set<String>>();
    String? uid = 'alice';
    final service = PartyModeService(
      currentUid: () => uid,
      approvedMembers: (_) => Stream.fromFuture(pending.future),
    );
    final rejected = expectLater(
      service.loadApprovedPartyUids('alice'),
      throwsStateError,
    );
    uid = null;
    pending.complete({'alice-private-peer'});
    await rejected;
  });
}
