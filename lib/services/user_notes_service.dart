import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";

class UserNotesService {
  UserNotesService._();

  static final UserNotesService instance = UserNotesService._();

  final Map<String, String> _notes = <String, String>{};

  Future<void> setNote(
      {String uid = "", String otherUid = "", required String text}) async {
    final key = uid.isNotEmpty ? uid : otherUid;
    if (key.isEmpty) return;
    _notes[key] = text;
  }

  Future<String> getNoteText({String uid = "", String otherUid = ""}) async {
    final key = uid.isNotEmpty ? uid : otherUid;
    return _notes[key] ?? "";
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchNote({
    String uid = "",
    String otherUid = "",
  }) {
    final key = uid.isNotEmpty ? uid : otherUid;
    return FirebaseFirestore.instance
        .collection("localUserNotes")
        .doc(key.isEmpty ? "empty" : key)
        .snapshots();
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
