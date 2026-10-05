import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/geoquery_service.dart';
import 'package:prox/services/party_mode_service.dart';
import 'package:prox/utils/auth_bound_stream.dart';
import 'package:prox/screens/services/matching/match_pipeline.dart';

void main() {
  test(
    'shared Party entry stream rejects a late peer result before the auth event arrives',
    () async {
      final accounts = StreamController<String?>.broadcast();
      final alice = StreamController<List<String>>.broadcast();
      final bob = StreamController<List<String>>.broadcast();
      String? current = 'alice';
      final seen = <List<String>>[];
      final errors = <Object>[];
      final subscription = authBoundStream<List<String>>(
        accountChanges: accounts.stream,
        currentUid: () => current,
        empty: const <String>[],
        watch: (uid) => uid == 'alice' ? alice.stream : bob.stream,
      ).listen(seen.add, onError: errors.add);
      await Future<void>.delayed(Duration.zero);
      current = 'bob';
      alice.add(['alice-private-peer']);
      alice.addError(StateError('private previous-account error'));
      await Future<void>.delayed(Duration.zero);
      expect(seen.every((entries) => entries.isEmpty), isTrue);
      expect(errors, isEmpty);
      accounts.add('bob');
      await Future<void>.delayed(Duration.zero);
      bob.add(['bob-approved-peer']);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ['bob-approved-peer']);
      await subscription.cancel();
      expect(alice.hasListener, isFalse);
      expect(bob.hasListener, isFalse);
      await accounts.close();
      await alice.close();
      await bob.close();
    },
  );
  test(
    'approved Party membership clears and cancels at account switches and sign-out',
    () async {
      final accounts = StreamController<String?>.broadcast();
      final alice = StreamController<Set<String>>.broadcast();
      final bob = StreamController<Set<String>>.broadcast();
      String? current = 'alice';
      final service = PartyModeService(
        currentUid: () => current,
        accountChanges: () => accounts.stream,
        approvedMembers: (uid) => uid == 'alice' ? alice.stream : bob.stream,
      );
      final values = <Set<String>>[];
      final subscription = service.watchApprovedPartyUids().listen(values.add);
      Future<void> flush() => Future<void>.delayed(Duration.zero);
      await flush();
      alice.add({'alice-approved'});
      await flush();
      expect(values.last, {'alice-approved'});
      current = 'bob';
      alice.add({'late-private-alice-peer'});
      await flush();
      expect(
        values.last,
        {'alice-approved'},
        reason: 'A snapshot from the previous credentials is discarded.',
      );
      accounts.add('bob');
      await flush();
      expect(values.last, isEmpty);
      expect(alice.hasListener, isFalse);
      bob.add({'bob-approved'});
      await flush();
      expect(values.last, {'bob-approved'});
      current = null;
      accounts.add(null);
      await flush();
      expect(values.last, isEmpty);
      expect(bob.hasListener, isFalse);
      await subscription.cancel();
      await accounts.close();
      await alice.close();
      await bob.close();
    },
  );

  test(
    'legacy profile partyId cannot earn a Party boost or admit an unapproved peer',
    () async {
      final pipeline = MatchPipeline(trustScoreForUid: (_) async => 0.5);
      const nearby = [
        NearbyDoc(
          uid: 'approved',
          distanceMiles: 1,
          loc: GeoPoint(0, 0),
          data: {},
        ),
        NearbyDoc(
          uid: 'spoofed',
          distanceMiles: 1,
          loc: GeoPoint(0, 0),
          data: {'partyId': 'legacy-id'},
        ),
      ];
      final public = await pipeline.buildCandidates(
        nearby: nearby,
        myPartyId: 'legacy-id',
        partyMemberUids: {'approved'},
      );
      expect(
        public
            .singleWhere((candidate) => candidate.uid == 'approved')
            .sameParty,
        isTrue,
      );
      expect(
        public.singleWhere((candidate) => candidate.uid == 'spoofed').sameParty,
        isFalse,
      );
      final scoped = await pipeline.buildCandidates(
        nearby: nearby,
        myPartyId: 'legacy-id',
        partyMemberUids: {'approved'},
        discovery: const MatchDiscoverySettings.defaults().copyWith(
          partyScope: MatchPartyScope.partyOnly,
        ),
      );
      expect(scoped.map((candidate) => candidate.uid), ['approved']);
    },
  );
}
