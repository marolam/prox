import 'dart:async';

/// Switch endless account data streams immediately and discard late old data.
Stream<T> authBoundStream<T>({
  required Stream<String?> accountChanges,
  required String? Function() currentUid,
  required Stream<T> Function(String uid) watch,
  required T empty,
}) {
  late StreamController<T> output;
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
    unawaited(data?.cancel());
    data = null;
    if (!output.isClosed) output.add(empty);
    if (uid == null || uid.isEmpty) return;
    data = watch(uid).listen(
      (value) {
        if (!output.isClosed && revision == generation && currentUid() == uid) {
          output.add(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!output.isClosed && revision == generation && currentUid() == uid) {
          output.addError(error, stack);
        }
      },
    );
  }

  output = StreamController<T>(
    onListen: () {
      bind(currentUid());
      accounts = accountChanges.listen(bind, onError: output.addError);
    },
    onCancel: () async {
      generation++;
      await accounts?.cancel();
      await data?.cancel();
    },
  );
  return output.stream;
}
