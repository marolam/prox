import "dart:async";

import "package:firebase_auth/firebase_auth.dart";

class UserNotesService {
  UserNotesService._()
    : _uidProvider = (() => FirebaseAuth.instance.currentUser?.uid ?? "");

  UserNotesService.forTesting({required String Function() uidProvider})
    : _uidProvider = uidProvider;

  static final UserNotesService instance = UserNotesService._();

  final Map<String, String> _notes = <String, String>{};
  final String Function() _uidProvider;
  final _changes = StreamController<String>.broadcast(sync: true);
  final Map<String, Stream<String>> _streams = {};

  String _key(String uid, String otherUid) {
    final owner = _uidProvider();
    final peer = uid.isNotEmpty ? uid : otherUid;
    return owner.isEmpty || peer.isEmpty ? "" : "$owner/$peer";
  }

  Future<void> setNote({
    String uid = "",
    String otherUid = "",
    required String text,
  }) async {
    final key = _key(uid, otherUid);
    if (key.isEmpty) return;
    _notes[key] = text;
    _changes.add(key);
  }

  Future<String> getNoteText({String uid = "", String otherUid = ""}) async {
    final key = _key(uid, otherUid);
    return _notes[key] ?? "";
  }

  Stream<String> watchNote({String uid = "", String otherUid = ""}) {
    final key = _key(uid, otherUid);
    if (key.isEmpty) return Stream.value("");
    return _streams.putIfAbsent(
      key,
      () => Stream<String>.multi((listener) {
        final subscription = _changes.stream.listen((changedKey) {
          if (changedKey == key && _key(uid, otherUid) == key) {
            listener.add(_notes[key] ?? "");
          }
        });
        listener.add(_key(uid, otherUid) == key ? (_notes[key] ?? "") : "");
        listener.onCancel = subscription.cancel;
      }, isBroadcast: true),
    );
  }
}

class NoteSaveDebouncer {
  Timer? _timer;

  void schedule(Duration delay, FutureOr<void> Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () async => action());
  }

  void run(Duration delay, Future<void> Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(action()));
  }

  void dispose() {
    _timer?.cancel();
  }
}
