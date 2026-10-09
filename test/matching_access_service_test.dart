import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/matching_access_service.dart';
import 'package:prox/models/user_settings.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  final clock = DateTime.utc(2026, 10, 7);
  Map<String, dynamic> location() => {
    'latitude': 0.0,
    'longitude': 0.0,
    'locationTs': clock.millisecondsSinceEpoch,
  };
  final unlocked = <String, dynamic>{
    'publicUnlocked': true,
    'publicUnlockedAt': 10,
    'partyScope': 'public',
    'checkedAt': clock.millisecondsSinceEpoch,
    'latitude': 0.0,
    'longitude': 0.0,
    'directUids': ['friend'],
    'treeMatches': [
      {
        'uid': 'tree',
        'mutualUids': ['friend'],
        'mutualNames': ['Morgan'],
      },
    ],
  };

  test(
    'refresh failure after an unlock closes public and graph access',
    () async {
      final receipts = StreamController<Map<String, dynamic>?>.broadcast();
      var fail = false;
      final service = MatchingAccessService(
        accountChanges: () => const Stream.empty(),
        currentUid: () => 'alice',
        watchReceipt: (_) => receipts.stream,
        loadAccess: (_) async {
          if (fail) throw StateError('Offline');
          return unlocked;
        },
        applyAccess: (_, _) {},
        currentLocation: location,
        now: () => clock,
      );
      await service.refresh();
      expect(service.current.publicUnlocked, isTrue);
      expect(service.current.treeMatches.keys, ['tree']);
      fail = true;
      await service.refresh(force: true);
      expect(service.current.publicUnlocked, isFalse);
      expect(service.current.directUids, isEmpty);
      expect(service.current.treeMatches, isEmpty);
      expect(service.lastError, isA<StateError>());
      service.dispose();
      await receipts.close();
    },
  );

  test(
    'late receipt and callable results cannot cross account boundaries',
    () async {
      final accounts = StreamController<String?>.broadcast();
      final alice = StreamController<Map<String, dynamic>?>.broadcast();
      final bob = StreamController<Map<String, dynamic>?>.broadcast();
      final aliceRequest = Completer<Map<String, dynamic>>();
      final bobRequest = Completer<Map<String, dynamic>>();
      String? current = 'alice';
      final service = MatchingAccessService(
        accountChanges: () => accounts.stream,
        currentUid: () => current,
        watchReceipt: (uid) => uid == 'alice' ? alice.stream : bob.stream,
        loadAccess: (uid) =>
            uid == 'alice' ? aliceRequest.future : bobRequest.future,
        applyAccess: (_, _) {},
        currentLocation: location,
        now: () => clock,
      );
      service.start();
      current = 'bob';
      alice.add(unlocked);
      aliceRequest.complete(unlocked);
      await flush();
      expect(service.current, MatchingAccessSnapshot.empty);
      accounts.add('bob');
      await flush();
      bobRequest.complete({
        'directUids': ['bob-friend'],
      });
      await flush();
      expect(service.current.directUids, {'bob-friend'});
      expect(service.current.publicUnlocked, isFalse);
      expect(alice.hasListener, isFalse);
      current = null;
      accounts.add(null);
      await flush();
      expect(service.current, MatchingAccessSnapshot.empty);
      expect(bob.hasListener, isFalse);
      service.dispose();
      await accounts.close();
      await alice.close();
      await bob.close();
    },
  );

  test(
    'graph invalidation clears edges and discards an older in-flight graph',
    () async {
      final receipts = StreamController<Map<String, dynamic>?>.broadcast();
      final requests = <Completer<Map<String, dynamic>>>[];
      final service = MatchingAccessService(
        accountChanges: () => const Stream.empty(),
        currentUid: () => 'alice',
        watchReceipt: (_) => receipts.stream,
        loadAccess: (_) {
          final request = Completer<Map<String, dynamic>>();
          requests.add(request);
          return request.future;
        },
        applyAccess: (_, _) {},
        currentLocation: location,
        now: () => clock,
      );
      service.start();
      requests[0].complete(unlocked);
      await flush();
      expect(service.current.directUids, {'friend'});
      final oldRequest = service.refresh(force: true);
      receipts.add({...unlocked, 'graphInvalidated': true});
      await flush();
      expect(service.current.directUids, isEmpty);
      expect(service.current.treeMatches, isEmpty);
      requests[1].complete(unlocked);
      await oldRequest;
      await flush();
      expect(service.current.directUids, isEmpty);
      expect(requests.length, 3);
      requests[2].complete({
        'directUids': ['new-friend'],
      });
      await flush();
      expect(service.current.directUids, {'new-friend'});
      service.dispose();
      await receipts.close();
    },
  );

  test(
    'a server acknowledgement prevents the unlock notice on a new session',
    () async {
      int? acknowledgedAt;
      int acknowledgements = 0;
      bool staleReply = false;
      MatchingAccessService create() => MatchingAccessService(
        accountChanges: () => const Stream.empty(),
        currentUid: () => 'alice',
        watchReceipt: (_) => const Stream.empty(),
        loadAccess: (_) async => {
          ...unlocked,
          'publicUnlockNotifiedAt': staleReply ? null : acknowledgedAt,
        },
        acknowledgeUnlock: (_) async {
          acknowledgements++;
          acknowledgedAt = 50;
        },
        applyAccess: (_, _) {},
        currentLocation: location,
        now: () => clock,
      );
      final first = create();
      await first.refresh();
      expect(first.current.publicUnlockNotificationPending, isTrue);
      await first.acknowledgePublicUnlock();
      expect(first.current.publicUnlockNotificationPending, isFalse);
      await first.acknowledgePublicUnlock();
      expect(acknowledgements, 1);
      staleReply = true;
      await first.refresh(force: true);
      expect(
        first.current.publicUnlockNotificationPending,
        isFalse,
        reason:
            'A delayed pre-acknowledgement reply cannot show the notice again.',
      );
      staleReply = false;
      first.dispose();
      final second = create();
      await second.refresh();
      expect(second.current.publicUnlockNotificationPending, isFalse);
      second.dispose();
    },
  );

  test(
    'canonical unlock receipt promotes immediately and preserves later private choices',
    () async {
      final receipts = StreamController<Map<String, dynamic>?>.broadcast();
      var scope = MatchPartyScope.tree;
      final service = MatchingAccessService(
        accountChanges: () => const Stream.empty(),
        currentUid: () => 'alice',
        watchReceipt: (_) => receipts.stream,
        loadAccess: (_) async => {'partyScope': 'tree'},
        currentLocation: location,
        now: () => clock,
        applyAccess: (access, canonical) {
          if (canonical)
            scope = switch (access.partyScope) {
              'public' => MatchPartyScope.public,
              'partyOnly' => MatchPartyScope.partyOnly,
              _ => MatchPartyScope.tree,
            };
        },
      );
      await service.refresh();
      receipts.add(unlocked);
      await flush();
      expect(scope, MatchPartyScope.public);
      for (final selected in [
        MatchPartyScope.tree,
        MatchPartyScope.partyOnly,
      ]) {
        service.recordLocalScopeSelection(selected);
        scope = selected;
        receipts.add(unlocked);
        await flush();
        expect(
          scope,
          selected,
          reason: 'A delayed public receipt cannot undo a choice.',
        );
        receipts.add({...unlocked, 'partyScope': selected.name});
        await flush();
        expect(scope, selected);
        receipts.add({...unlocked, 'partyScope': selected.name});
        await flush();
        expect(
          scope,
          selected,
          reason: 'Repeated unlock refresh keeps the saved private scope.',
        );
      }
      service.dispose();
      await receipts.close();
    },
  );

  test('stale and previous-area live receipts cannot unlock public', () async {
    final receipts = StreamController<Map<String, dynamic>?>.broadcast();
    var longitude = 0.0;
    final applied = <bool>[];
    final service = MatchingAccessService(
      accountChanges: () => const Stream.empty(),
      currentUid: () => 'alice',
      watchReceipt: (_) => receipts.stream,
      loadAccess: (_) async => unlocked,
      currentLocation: () => {...location(), 'longitude': longitude},
      now: () => clock,
      applyAccess: (access, _) => applied.add(access.publicUnlocked),
    );
    await service.refresh();
    expect(service.current.publicUnlocked, isTrue);
    receipts.add({
      ...unlocked,
      'checkedAt': clock
          .subtract(const Duration(minutes: 16))
          .millisecondsSinceEpoch,
    });
    await flush();
    expect(service.current.publicUnlocked, isFalse);
    expect(applied.last, isFalse);
    receipts.add(unlocked);
    await flush();
    expect(service.current.publicUnlocked, isTrue);
    longitude = 1;
    expect(
      service.current.publicUnlocked,
      isFalse,
      reason: 'Movement closes the old area before a network result arrives.',
    );
    receipts.add(unlocked);
    await flush();
    expect(service.current.publicUnlocked, isFalse);
    expect(applied.last, isFalse);
    expect(
      service.current.directUids,
      {'friend'},
      reason: 'Area density does not remove in-person connections.',
    );
    service.dispose();
    await receipts.close();
  });
}
