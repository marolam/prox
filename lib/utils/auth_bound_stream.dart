import 'dart:async';

/// Watch account data independently for each listener, without replaying it.
///
/// The account stream must support multiple listeners, and [watch] must return
/// a stream that can be listened to for each invocation. Cancelling one consumer
/// only cancels that consumer's subscriptions. This also allows lazy widgets to
/// unmount and later listen to the same returned stream again.
Stream<T> authBoundStream<T>({
  required Stream<String?> accountChanges,
  required String? Function() currentUid,
  required Stream<T> Function(String uid) watch,
  required T empty,
}) {
  final events = Stream<_AccountStreamEvent<T>>.multi((output) {
    StreamSubscription<String?>? accounts;
    StreamSubscription<T>? data;
    String? boundUid;
    var generation = 0;
    var initialized = false;

    void bind(String? uid) {
      if (initialized && uid == boundUid) return;
      initialized = true;
      boundUid = uid;
      final revision = ++generation;
      bool isCurrent() => revision == generation && currentUid() == uid;
      unawaited(data?.cancel());
      data = null;
      output.add(_AccountStreamEvent(isCurrent, (sink) => sink.add(empty)));
      if (uid == null || uid.isEmpty) return;
      void addError(Object error, StackTrace stack) {
        if (isCurrent()) {
          output.add(
            _AccountStreamEvent(
              isCurrent,
              (sink) => sink.addError(error, stack),
            ),
          );
        }
      }

      try {
        data = watch(uid).listen((value) {
          if (isCurrent()) {
            output.add(
              _AccountStreamEvent(isCurrent, (sink) => sink.add(value)),
            );
          }
        }, onError: addError);
      } catch (error, stack) {
        addError(error, stack);
      }
    }

    output.onCancel = () async {
      generation++;
      await Future.wait([
        if (accounts != null) accounts.cancel(),
        if (data != null) data!.cancel(),
      ]);
    };
    bind(currentUid());
    accounts = accountChanges.listen(
      bind,
      onError: (Object error, StackTrace stack) {
        final revision = generation;
        final uid = boundUid;
        output.add(
          _AccountStreamEvent(
            () => revision == generation && currentUid() == uid,
            (sink) => sink.addError(error, stack),
          ),
        );
      },
    );
  }, isBroadcast: true);

  // Check again when a queued or paused event is delivered. Credentials may
  // change after the source callback, before the auth event reaches this stream.
  return events.transform(
    StreamTransformer<_AccountStreamEvent<T>, T>.fromHandlers(
      handleData: (event, sink) {
        if (event.isCurrent()) event.deliver(sink);
      },
    ),
  );
}

class _AccountStreamEvent<T> {
  const _AccountStreamEvent(this.isCurrent, this.deliver);

  final bool Function() isCurrent;
  final void Function(EventSink<T> sink) deliver;
}
