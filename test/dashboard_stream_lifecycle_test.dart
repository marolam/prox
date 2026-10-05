import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/utils/auth_bound_stream.dart';

void main() {
  testWidgets(
    'dashboard Party card can leave the lazy viewport and mount again',
    (tester) async {
      final accounts = StreamController<String?>.broadcast();
      final party = StreamController<List<String>>.broadcast();
      var watches = 0;
      final stream = authBoundStream<List<String>>(
        accountChanges: accounts.stream,
        currentUid: () => 'alice',
        watch: (_) {
          watches++;
          return party.stream;
        },
        empty: const <String>[],
      );
      final scroll = ScrollController();
      final cardKey = GlobalKey();
      // Dashboard builds a fixed list of children. Its StreamBuilder widget and
      // stream survive scrolling while the lazy viewport disposes their State.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scroll,
              cacheExtent: 0,
              children: [
                const SizedBox(height: 80, child: Text('Your snapshot')),
                StreamBuilder<List<String>>(
                  key: cardKey,
                  stream: stream,
                  builder: (_, snapshot) => SizedBox(
                    height: 80,
                    child: Text('Party: ${snapshot.data?.length ?? 0}'),
                  ),
                ),
                const SizedBox(height: 3200),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      party.add(['approved-peer']);
      await tester.pumpAndSettle();
      expect(find.text('Party: 1'), findsOneWidget);
      expect(watches, 1);

      scroll.jumpTo(2200);
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pump();
      expect(
        cardKey.currentState,
        isNull,
        reason: 'The actual subscription owner was disposed.',
      );
      expect(accounts.hasListener, isFalse);
      expect(party.hasListener, isFalse);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(cardKey.currentState, isNotNull);
      expect(watches, 2);
      party.add(['approved-peer', 'another-peer']);
      await tester.pumpAndSettle();
      expect(find.text('Party: 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      scroll.dispose();
      await accounts.close();
      await party.close();
    },
  );

  test(
    'concurrent consumers cancel independently and the survivor keeps updates',
    () async {
      final accounts = StreamController<String?>.broadcast();
      final party = StreamController<List<String>>.broadcast();
      var watches = 0;
      final stream = authBoundStream<List<String>>(
        accountChanges: accounts.stream,
        currentUid: () => 'alice',
        watch: (_) {
          watches++;
          return party.stream;
        },
        empty: const <String>[],
      );
      final first = <List<String>>[], second = <List<String>>[];
      expect(stream.isBroadcast, isTrue);
      final a = stream.listen(first.add);
      final b = stream.listen(second.add);
      await Future<void>.delayed(Duration.zero);
      party.add(['approved-peer']);
      await Future<void>.delayed(Duration.zero);
      expect(watches, 2);
      expect(first.last, ['approved-peer']);
      expect(second.last, ['approved-peer']);
      await a.cancel();
      party.add(['surviving-update']);
      await Future<void>.delayed(Duration.zero);
      expect(first.last, ['approved-peer']);
      expect(second.last, ['surviving-update']);
      await b.cancel();
      expect(accounts.hasListener, isFalse);
      expect(party.hasListener, isFalse);
      await accounts.close();
      await party.close();
    },
  );

  test(
    'a remounted consumer starts from current credentials without private replay',
    () async {
      final accounts = StreamController<String?>.broadcast();
      final alice = StreamController<List<String>>.broadcast();
      final bob = StreamController<List<String>>.broadcast();
      String? uid = 'alice';
      final stream = authBoundStream<List<String>>(
        accountChanges: accounts.stream,
        currentUid: () => uid,
        watch: (owner) => owner == 'alice' ? alice.stream : bob.stream,
        empty: const <String>[],
      );
      final old = <List<String>>[];
      final first = stream.listen(old.add);
      await Future<void>.delayed(Duration.zero);
      alice.add(['alice-private-peer']);
      await Future<void>.delayed(Duration.zero);
      expect(old.last, ['alice-private-peer']);
      await first.cancel();
      uid = 'bob'; // No observer existed when the account event was dispatched.
      final fresh = <List<String>>[];
      final second = stream.listen(fresh.add);
      await Future<void>.delayed(Duration.zero);
      expect(fresh, [<String>[]]);
      alice.add(['late-alice-peer']);
      bob.add(['bob-approved-peer']);
      await Future<void>.delayed(Duration.zero);
      expect(fresh.last, ['bob-approved-peer']);
      expect(
        fresh.any((peers) => peers.contains('alice-private-peer')),
        isFalse,
      );
      await second.cancel();
      await accounts.close();
      await alice.close();
      await bob.close();
    },
  );

  test(
    'queued account data and errors are discarded if credentials change before delivery',
    () async {
      final accounts = StreamController<String?>.broadcast(sync: true);
      final alice = StreamController<List<String>>.broadcast(sync: true);
      final bob = StreamController<List<String>>.broadcast(sync: true);
      String? uid = 'alice';
      final seen = <List<String>>[], errors = <Object>[];
      final subscription = authBoundStream<List<String>>(
        accountChanges: accounts.stream,
        currentUid: () => uid,
        watch: (owner) => owner == 'alice' ? alice.stream : bob.stream,
        empty: const <String>[],
      ).listen(seen.add, onError: errors.add);
      await Future<void>.delayed(Duration.zero);
      alice.add(['queued-private-peer']);
      alice.addError(StateError('queued-private-account-error'));
      uid = 'bob';
      await Future<void>.delayed(Duration.zero);
      expect(seen.every((peers) => peers.isEmpty), isTrue);
      expect(errors, isEmpty);
      accounts.add('bob');
      await Future<void>.delayed(Duration.zero);
      bob.add(['current-approved-peer']);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ['current-approved-peer']);
      await subscription.cancel();
      await accounts.close();
      await alice.close();
      await bob.close();
    },
  );

  test(
    'paused consumers drop buffered data and errors from a previous account',
    () async {
      final accounts = StreamController<String?>.broadcast(sync: true);
      final alice = StreamController<List<String>>.broadcast(sync: true);
      final bob = StreamController<List<String>>.broadcast(sync: true);
      String? uid = 'alice';
      final seen = <List<String>>[], errors = <Object>[];
      final subscription = authBoundStream<List<String>>(
        accountChanges: accounts.stream,
        currentUid: () => uid,
        watch: (owner) => owner == 'alice' ? alice.stream : bob.stream,
        empty: const <String>[],
      ).listen(seen.add, onError: errors.add);
      await Future<void>.delayed(Duration.zero);
      subscription.pause();
      alice.add(['buffered-private-peer']);
      alice.addError(StateError('buffered-private-account-error'));
      uid = 'bob';
      accounts.add('bob');
      bob.add(['bob-approved-peer']);
      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(seen, [
        <String>[],
        <String>[],
        ['bob-approved-peer'],
      ]);
      expect(errors, isEmpty);
      uid = null;
      accounts.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isEmpty);
      await subscription.cancel();
      expect(accounts.hasListener, isFalse);
      expect(bob.hasListener, isFalse);
      await accounts.close();
      await alice.close();
      await bob.close();
    },
  );
}
