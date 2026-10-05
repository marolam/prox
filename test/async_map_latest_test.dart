import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/utils/async_map_latest.dart';

void main() {
  test(
    'slow reads skip obsolete snapshots and preserve bounded concurrency',
    () async {
      final source = StreamController<int>();
      final first = Completer<int>();
      final started = Completer<void>();
      final converted = <int>[];
      final result = asyncMapLatest(source.stream, (int value) {
        converted.add(value);
        if (value == 1) {
          started.complete();
          return first.future;
        }
        return Future.value(value);
      }).toList();
      source.add(1);
      await started.future;
      for (var i = 2; i <= 60; i++) source.add(i);
      await source.close();
      expect(converted, [1]);
      first.complete(1);
      expect(await result, [60]);
      expect(converted, [1, 60]);
    },
  );

  test('obsolete lookup errors cannot replace newer valid results', () async {
    final source = StreamController<int>();
    final old = Completer<int>();
    final started = Completer<void>();
    final result = asyncMapLatest(source.stream, (int value) {
      if (value == 1) {
        started.complete();
        return old.future;
      }
      return Future.value(value);
    }).toList();
    source.add(1);
    await started.future;
    source.add(2);
    await source.close();
    old.completeError(StateError('obsolete read'));
    expect(await result, [2]);
  });

  test('cancellation stops queued work and late results', () async {
    final source = StreamController<int>();
    final old = Completer<int>();
    final started = Completer<void>();
    final results = <int>[];
    final converted = <int>[];
    final subscription = asyncMapLatest(source.stream, (int value) {
      converted.add(value);
      started.complete();
      return old.future;
    }).listen(results.add);
    source.add(1);
    await started.future;
    source.add(2);
    await subscription.cancel();
    old.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(results, isEmpty);
    expect(converted, [1]);
    await source.close();
  });

  test('current lookup failures reach the caller', () async {
    await expectLater(
      asyncMapLatest(
        Stream.value(1),
        (_) async => throw StateError('read failed'),
      ),
      emitsError(isA<StateError>()),
    );
  });
}
