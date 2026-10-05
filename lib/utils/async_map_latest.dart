import 'dart:async';

/// Keep one conversion in flight and only the newest pending source event.
/// Unlike Stream.asyncMap, slow reads cannot build a queue of obsolete snapshots.
Stream<R> asyncMapLatest<T, R>(
  Stream<T> source,
  Future<R> Function(T) convert,
) {
  late StreamController<R> controller;
  StreamSubscription<T>? subscription;
  T? latest;
  var pending = false;
  var running = false;
  var done = false;
  var cancelled = false;
  var revision = 0;

  Future<void> drain() async {
    if (running) return;
    running = true;
    while (pending && !cancelled) {
      final item = latest as T;
      final current = revision;
      pending = false;
      try {
        final result = await convert(item);
        if (!cancelled && current == revision) controller.add(result);
      } catch (error, stack) {
        if (!cancelled && current == revision)
          controller.addError(error, stack);
      }
    }
    running = false;
    if (done && !cancelled) await controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      subscription = source.listen(
        (event) {
          latest = event;
          pending = true;
          revision++;
          unawaited(drain());
        },
        onError: (Object error, StackTrace stack) {
          // A source failure invalidates a conversion based on older data.
          revision++;
          pending = false;
          controller.addError(error, stack);
        },
        onDone: () {
          done = true;
          if (!running) unawaited(controller.close());
        },
      );
    },
    onCancel: () async {
      cancelled = true;
      pending = false;
      latest = null;
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
