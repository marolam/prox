import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/geoquery_service.dart';
import 'package:prox/services/matching/matching_runtime_service.dart';
import 'package:prox/services/user_profile_service.dart';

UserProfile profile(String uid) => UserProfile(
  uid: uid,
  searchingFor: const ['gardening'],
  canProvide: const ['cooking'],
);

const peer = NearbyDoc(
  uid: 'peer',
  distanceMiles: 1,
  loc: GeoPoint(0, 0),
  data: {
    'modeKind': 'normal',
    'normalMode': 'active',
    'keywords': {
      'Searching For': ['cooking'],
      'Can Provide': ['gardening'],
    },
  },
);

void main() {
  test(
    'overlapping keyword requests share one profile read per account',
    () async {
      final reads = <String, int>{};
      final service = MatchingRuntimeService.forTesting(
        uidProvider: () => 'me',
        profileLoader: (uid) async {
          reads.update(uid, (count) => count + 1, ifAbsent: () => 1);
          await Future<void>.delayed(Duration.zero);
          return profile(uid);
        },
      );
      final results = await Future.wait([
        service.sharedKeywordsWith('peer'),
        service.sharedKeywordsWith('peer'),
      ]);
      expect(results, everyElement(contains('gardening')));
      expect(reads, {'me': 1, 'peer': 1});
    },
  );

  test(
    'account changes during the first profile read discard old candidates',
    () async {
      String? uid = 'account-a';
      final pending = Completer<UserProfile?>();
      final started = Completer<void>();
      final service = MatchingRuntimeService.forTesting(
        uidProvider: () => uid,
        profileLoader: (requested) {
          if (requested == 'account-a') {
            started.complete();
            return pending.future;
          }
          return Future.value(profile(requested));
        },
      );
      final result = service.filterByModeForSettings(
        [peer],
        const MatchDiscoverySettings.defaults().copyWith(
          modeKind: MatchingModeKind.normal,
          normalMode: NormalMatchMode.active,
        ),
      );
      await started.future;
      uid = 'account-b';
      pending.complete(profile('account-a'));
      expect(await result, isEmpty);
      expect(await service.sharedKeywordsWith('peer'), contains('gardening'));
    },
  );

  test(
    'account changes during strict matching discard the complete result',
    () async {
      String? uid = 'account-a';
      final pendingPeer = Completer<UserProfile?>();
      final peerRequested = Completer<void>();
      final service = MatchingRuntimeService.forTesting(
        uidProvider: () => uid,
        profileLoader: (requested) {
          if (requested == 'peer') {
            peerRequested.complete();
            return pendingPeer.future;
          }
          return Future.value(profile(requested));
        },
      );
      final result = service.filterByModeForSettings(
        [peer],
        const MatchDiscoverySettings.defaults().copyWith(
          modeKind: MatchingModeKind.normal,
          normalMode: NormalMatchMode.active,
          keywordMode: KeywordMatchMode.strict,
        ),
      );
      await peerRequested.future;
      uid = null;
      pendingPeer.complete(profile('peer'));
      expect(await result, isEmpty);
    },
  );

  test(
    'clearing a session invalidates both shared keywords and treasure ranking',
    () async {
      final pendingPeer = Completer<UserProfile?>();
      final peerRequested = Completer<void>();
      final service = MatchingRuntimeService.forTesting(
        uidProvider: () => 'account-a',
        profileLoader: (requested) {
          if (requested == 'peer') {
            peerRequested.complete();
            return pendingPeer.future;
          }
          return Future.value(profile(requested));
        },
      );
      final shared = service.sharedKeywordsWith('peer');
      final ranked = service.rankTreasureTargets([peer]);
      await peerRequested.future;
      service.clearSession();
      pendingPeer.complete(profile('peer'));
      expect(await shared, isEmpty);
      expect(await ranked, isEmpty);
    },
  );
}
