import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";

class MeetupFocusLockState {
  final bool active;
  final String meetupId;
  final String otherUid;

  const MeetupFocusLockState({
    required this.active,
    required this.meetupId,
    required this.otherUid,
  });

  static const MeetupFocusLockState inactive = MeetupFocusLockState(
    active: false,
    meetupId: "",
    otherUid: "",
  );

  bool sameAs(MeetupFocusLockState other) {
    return active == other.active &&
        meetupId == other.meetupId &&
        otherUid == other.otherUid;
  }
}

class MeetupFocusLockService extends ChangeNotifier {
  MeetupFocusLockService._();

  static const Duration _fallbackRequestWindow = Duration(minutes: 10);
  static const Duration _fallbackLiveWindow = Duration(minutes: 15);

  static final MeetupFocusLockService instance = MeetupFocusLockService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _aSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bSub;

  final Map<String, Map<String, dynamic>> _aDocs = <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _bDocs = <String, Map<String, dynamic>>{};

  String _uid = "";
  MeetupFocusLockState _state = MeetupFocusLockState.inactive;

  MeetupFocusLockState get state => _state;
  bool get isLocked => _state.active;
  String get activeMeetupId => _state.meetupId;
  String get activeOtherUid => _state.otherUid;

  bool canInteractWithChat(String chatId) {
    final id = chatId.trim();
    if (!isLocked) return true;
    if (id.isEmpty) return false;
    return id == activeMeetupId;
  }

  Future<void> ensureStarted() async {
    if (_authSub != null) return;

    _authSub = _auth.authStateChanges().listen((user) {
      final uid = user?.uid ?? "";
      _switchUid(uid);
    });

    _switchUid(_auth.currentUser?.uid ?? "");
  }

  Future<bool> isUserBusy(String uid) async {
    final safeUid = uid.trim();
    if (safeUid.isEmpty) return false;
    try {
      final snap = await _db.collection("users").doc(safeUid).get();
      final data = snap.data() ?? <String, dynamic>{};
      final lock = data["interactionLock"];
      if (lock is Map && lock["busyInMeetup"] == true) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _switchUid(String uid) {
    final safeUid = uid.trim();
    if (_uid == safeUid) return;

    _uid = safeUid;
    _aSub?.cancel();
    _bSub?.cancel();
    _aSub = null;
    _bSub = null;
    _aDocs.clear();
    _bDocs.clear();

    if (_uid.isEmpty) {
      _updateState(MeetupFocusLockState.inactive);
      return;
    }

    _aSub = _db
        .collection("meetups")
        .where("aUid", isEqualTo: _uid)
        .limit(100)
        .snapshots()
        .listen((snap) {
      _aDocs
        ..clear()
        ..addEntries(
          snap.docs.map(
            (d) => MapEntry<String, Map<String, dynamic>>(d.id, d.data()),
          ),
        );
      _recompute();
    }, onError: (Object _) {
      // Fail open on listener auth/rules errors so stale local lock state
      // never traps users outside the normal tabs.
      _aDocs.clear();
      _recompute();
    });

    _bSub = _db
        .collection("meetups")
        .where("bUid", isEqualTo: _uid)
        .limit(100)
        .snapshots()
        .listen((snap) {
      _bDocs
        ..clear()
        ..addEntries(
          snap.docs.map(
            (d) => MapEntry<String, Map<String, dynamic>>(d.id, d.data()),
          ),
        );
      _recompute();
    }, onError: (Object _) {
      _bDocs.clear();
      _recompute();
    });
  }

  bool _isTerminalStatus(String status) {
    return status == "completed" ||
        status == "canceled" ||
        status == "cancelled" ||
        status == "expired" ||
        status == "declined" ||
        status == "auto_closed" ||
        status == "purged";
  }

  bool _isActiveStatus(String status) {
    return status == "requested" || status == "accepted" || status == "live";
  }

  bool _isEffectivelyExpired(Map<String, dynamic> d) {
    final dynamic expiresAt = d["expiresAt"];
    if (expiresAt is Timestamp) {
      return expiresAt.toDate().isBefore(DateTime.now());
    }

    final String status = (d["status"] ?? "").toString().trim();
    if (status == "requested") {
      final requestedAt = d["requestedAt"];
      if (requestedAt is Timestamp) {
        final DateTime deadline =
            requestedAt.toDate().add(_fallbackRequestWindow);
        return deadline.isBefore(DateTime.now());
      }
    }

    if (status == "accepted" || status == "live") {
      final startedAt = d["startedAt"];
      if (startedAt is Timestamp) {
        final DateTime deadline = startedAt.toDate().add(_fallbackLiveWindow);
        return deadline.isBefore(DateTime.now());
      }
    }

    if (status == "requested" || status == "accepted" || status == "live") {
      final updatedAt = d["updatedAt"];
      if (updatedAt is Timestamp) {
        final Duration maxAge = status == "requested"
            ? _fallbackRequestWindow
            : _fallbackLiveWindow;
        final DateTime deadline = updatedAt.toDate().add(maxAge);
        if (deadline.isBefore(DateTime.now())) {
          return true;
        }
      }
    }

    return false;
  }

  int _updatedTsMs(Map<String, dynamic> d) {
    final updated = d["updatedAt"];
    if (updated is Timestamp) return updated.millisecondsSinceEpoch;
    final completed = d["completedAt"];
    if (completed is Timestamp) return completed.millisecondsSinceEpoch;
    final accepted = d["acceptedAt"];
    if (accepted is Timestamp) return accepted.millisecondsSinceEpoch;
    final requested = d["requestedAt"];
    if (requested is Timestamp) return requested.millisecondsSinceEpoch;
    return 0;
  }

  void _recompute() {
    if (_uid.isEmpty) {
      _updateState(MeetupFocusLockState.inactive);
      return;
    }

    final all = <String, Map<String, dynamic>>{}
      ..addAll(_aDocs)
      ..addAll(_bDocs);

    String bestId = "";
    String bestOther = "";
    int bestTs = -1;

    for (final entry in all.entries) {
      final d = entry.value;
      final status = (d["status"] ?? "").toString().trim();
      if (!_isActiveStatus(status)) continue;
      if (_isTerminalStatus(status)) continue;
      if (_isEffectivelyExpired(d)) continue;

      final ts = _updatedTsMs(d);
      if (ts < bestTs) continue;

      final aUid = (d["aUid"] ?? "").toString().trim();
      final bUid = (d["bUid"] ?? "").toString().trim();
      final other = (aUid == _uid) ? bUid : ((bUid == _uid) ? aUid : "");

      bestTs = ts;
      bestId = entry.key;
      bestOther = other;
    }

    if (bestId.isEmpty) {
      _updateState(MeetupFocusLockState.inactive);
      return;
    }

    _updateState(MeetupFocusLockState(
      active: true,
      meetupId: bestId,
      otherUid: bestOther,
    ));
  }

  void _updateState(MeetupFocusLockState next) {
    if (_state.sameAs(next)) return;
    _state = next;
    notifyListeners();
    unawaited(_publishBusyStatus());
  }

  Future<void> _publishBusyStatus() async {
    final uid = _uid.trim();
    if (uid.isEmpty) return;

    final bool active = _state.active;
    final String tag = active ? "In active meetup" : "";

    try {
      await _db.collection("users").doc(uid).set(<String, Object?>{
        "interactionLock": <String, Object?>{
          "busyInMeetup": active,
          "activeMeetupId": active ? _state.meetupId : "",
          "activeMeetupOtherUid": active ? _state.otherUid : "",
          "statusTag": tag,
          "updatedAt": FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (_) {}

    try {
      await _db
          .collection("users")
          .doc(uid)
          .collection("presence")
          .doc("current")
          .set(<String, Object?>{
        "busyInMeetup": active,
        "interactionStatusTag": tag,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
