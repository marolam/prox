import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/points_service.dart';
import 'package:prox/widgets/prox_trust_bar.dart';

class _TrustSource implements TrustBarSource {
  String? uid = 'alice';
  final accounts = StreamController<String?>.broadcast(sync: true);
  final scores = <String, StreamController<PointsMeta>>{};
  final watched = <String>[];
  int authFactories = 0;

  StreamController<PointsMeta> score(String uid) => scores.putIfAbsent(
    uid,
    () => StreamController<PointsMeta>.broadcast(sync: true),
  );

  @override
  String? get currentUid => uid;

  @override
  Stream<String?> watchUid() {
    authFactories++;
    // Model Firebase Auth's cancel-on-last-listener broadcast wrapper: this
    // particular wrapper cannot be reused after its subscription is cancelled.
    return accounts.stream.asBroadcastStream(
      onCancel: (subscription) => subscription.cancel(),
    );
  }

  @override
  Stream<PointsMeta> watchMeta(String uid) {
    watched.add(uid);
    return score(uid).stream;
  }

  void changeAccount(String? next) {
    uid = next;
    accounts.add(next);
  }

  void emit(String uid, double trust) =>
      score(uid).add(PointsMeta.empty.copyWith(trustPercent: trust));

  Future<void> close() async {
    await accounts.close();
    await Future.wait(scores.values.map((controller) => controller.close()));
  }
}

Widget _app(_TrustSource source) => MaterialApp(
  home: Scaffold(body: CurrentUserTrustBar(source: source)),
);

Future<void> _flush(WidgetTester tester) async {
  // Loading is an indeterminate progress indicator, so do not wait for all
  // animation frames to settle before the score is available.
  await tester.pump();
  await tester.pump();
}

Future<void> _dispose(WidgetTester tester, _TrustSource source) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flush(tester);
  await source.close();
}

void main() {
  testWidgets('shows loading then the canonical score and live changes', (
    tester,
  ) async {
    final source = _TrustSource();
    await tester.pumpWidget(_app(source));
    await _flush(tester);
    expect(find.text('Loading trust…'), findsOneWidget);
    expect(find.text('Trust 80%'), findsNothing);

    source.emit('alice', 100);
    await _flush(tester);
    expect(find.text('Trust 100%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    source.emit('alice', 61.4);
    await _flush(tester);
    expect(find.text('Trust 61%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(0.614, 0.000001),
    );
    await _dispose(tester, source);
  });

  testWidgets('a loaded zero is a real score rather than an unknown state', (
    tester,
  ) async {
    final source = _TrustSource();
    await tester.pumpWidget(_app(source));
    await _flush(tester);
    expect(find.text('Trust 0%'), findsNothing);
    source.emit('alice', 0);
    await _flush(tester);
    expect(find.text('Trust 0%'), findsOneWidget);
    expect(find.text('Loading trust…'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    await _dispose(tester, source);
  });

  testWidgets('read errors clear the score and allow a fresh retry', (
    tester,
  ) async {
    final source = _TrustSource();
    await tester.pumpWidget(_app(source));
    await _flush(tester);
    source.emit('alice', 100);
    await _flush(tester);
    source.score('alice').addError(StateError('private server details'));
    await _flush(tester);
    expect(find.text('Trust 100%'), findsNothing);
    expect(find.text('Trust unavailable'), findsOneWidget);
    expect(find.textContaining('private server details'), findsNothing);

    await tester.tap(find.text('Retry'));
    await _flush(tester);
    expect(source.authFactories, 2);
    expect(source.watched, ['alice', 'alice']);
    expect(find.text('Loading trust…'), findsOneWidget);
    source.emit('alice', 88);
    await _flush(tester);
    expect(find.text('Trust 88%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester, source);
  });

  testWidgets('account changes and sign-out clear old private trust', (
    tester,
  ) async {
    final source = _TrustSource();
    await tester.pumpWidget(_app(source));
    await _flush(tester);
    source.emit('alice', 100);
    await _flush(tester);
    source.changeAccount('bob');
    await _flush(tester);
    expect(find.text('Trust 100%'), findsNothing);
    expect(find.text('Loading trust…'), findsOneWidget);
    expect(source.score('alice').hasListener, isFalse);
    source.emit('alice', 19);
    source.score('alice').addError(StateError('late Alice error'));
    await _flush(tester);
    expect(find.text('Trust 19%'), findsNothing);
    expect(find.text('Trust unavailable'), findsNothing);
    source.emit('bob', 40);
    await _flush(tester);
    expect(find.text('Trust 40%'), findsOneWidget);

    source.changeAccount(null);
    await _flush(tester);
    source.emit('bob', 57);
    await _flush(tester);
    expect(find.text('Trust 40%'), findsNothing);
    expect(find.text('Trust 57%'), findsNothing);
    expect(find.text('Sign in to view trust.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await _dispose(tester, source);
  });

  testWidgets('a parent rebuild rejects values before auth reset delivery', (
    tester,
  ) async {
    final source = _TrustSource();
    await tester.pumpWidget(_app(source));
    await _flush(tester);
    source.emit('alice', 100);
    await _flush(tester);
    source.emit('alice', 77); // Queued while Alice was still current.
    source.uid = 'bob'; // SDK credentials change before the auth event arrives.
    await tester.pumpWidget(_app(source));
    await _flush(tester);
    expect(find.text('Trust 100%'), findsNothing);
    expect(find.text('Trust 77%'), findsNothing);
    expect(find.text('Loading trust…'), findsOneWidget);

    source.accounts.add('bob');
    await _flush(tester);
    source.emit('bob', 25);
    await _flush(tester);
    expect(find.text('Trust 25%'), findsOneWidget);
    await _dispose(tester, source);
  });

  testWidgets('remove and reopen creates fresh auth and score listeners', (
    tester,
  ) async {
    final source = _TrustSource();
    await tester.pumpWidget(_app(source));
    await _flush(tester);
    source.emit('alice', 70);
    await _flush(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _flush(tester);
    expect(source.accounts.hasListener, isFalse);
    expect(source.score('alice').hasListener, isFalse);

    await tester.pumpWidget(_app(source));
    await _flush(tester);
    expect(source.authFactories, 2);
    expect(source.watched, ['alice', 'alice']);
    expect(find.text('Trust 70%'), findsNothing);
    expect(find.text('Loading trust…'), findsOneWidget);
    source.emit('alice', 100);
    await _flush(tester);
    source.changeAccount('bob');
    await _flush(tester);
    source.emit('bob', 30);
    await _flush(tester);
    expect(find.text('Trust 100%'), findsNothing);
    expect(find.text('Trust 30%'), findsOneWidget);
    expect(source.watched, ['alice', 'alice', 'bob']);
    expect(tester.takeException(), isNull);
    await _dispose(tester, source);
  });

  testWidgets('replacing the source never reuses its previous cached score', (
    tester,
  ) async {
    final first = _TrustSource();
    final next = _TrustSource();
    await tester.pumpWidget(_app(first));
    await _flush(tester);
    first.emit('alice', 100);
    await _flush(tester);
    await tester.pumpWidget(_app(next));
    await _flush(tester);
    expect(find.text('Trust 100%'), findsNothing);
    expect(find.text('Loading trust…'), findsOneWidget);
    expect(first.accounts.hasListener, isFalse);
    first.emit('alice', 75);
    next.emit('alice', 0);
    await _flush(tester);
    expect(find.text('Trust 75%'), findsNothing);
    expect(find.text('Trust 0%'), findsOneWidget);
    await _dispose(tester, next);
    await first.close();
  });

  testWidgets('invalid numeric metadata is unavailable instead of fabricated', (
    tester,
  ) async {
    final source = _TrustSource();
    await tester.pumpWidget(_app(source));
    await _flush(tester);
    source.emit('alice', double.nan);
    await _flush(tester);
    expect(find.text('Trust unavailable'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);
    await _dispose(tester, source);
  });
}
