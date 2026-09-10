import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Watches the backend's active-mode policy; clients never write penalties.
class ActiveModePolicyService extends ChangeNotifier {
  ActiveModePolicyService._();
  static final ActiveModePolicyService instance = ActiveModePolicyService._();
  StreamSubscription<User?>? _auth;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _policy;
  Timer? _expiry;
  String? _uid;
  int _lockUntilMs = 0;
  Object? lastError;

  bool get isLockedByBackend =>
      _lockUntilMs > DateTime.now().millisecondsSinceEpoch;

  void ensureWatching() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen(
      (user) => _watch(user?.uid),
    );
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != uid) _watch(uid);
  }

  void _watch(String? uid) {
    if (_uid == uid && _policy != null) return;
    _uid = uid;
    unawaited(_policy?.cancel());
    _policy = null;
    _expiry?.cancel();
    _lockUntilMs = 0;
    lastError = null;
    notifyListeners();
    if (uid == null) return;
    _policy = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meta')
        .doc('matching')
        .snapshots()
        .listen(
          (snapshot) {
            if (_uid != uid) return;
            _apply(snapshot.data());
          },
          onError: (Object error) {
            if (_uid != uid) return;
            lastError = error;
            notifyListeners();
          },
        );
  }

  void _apply(Map<String, dynamic>? data) {
    _lockUntilMs = (data?['lockUntilEpochMs'] as num?)?.toInt() ?? 0;
    lastError = null;
    _expiry?.cancel();
    final remaining = _lockUntilMs - DateTime.now().millisecondsSinceEpoch;
    if (remaining > 0)
      _expiry = Timer(Duration(milliseconds: remaining), notifyListeners);
    notifyListeners();
  }

  Future<void> evaluateAndApplyPenaltyIfNeeded() async {
    ensureWatching();
    final uid = _uid;
    if (uid == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('matching')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (_uid == uid) _apply(snapshot.data());
    } catch (error) {
      if (_uid != uid) return;
      // Preserve the last known backend lock through connection loss.
      lastError = error;
      notifyListeners();
    }
  }
}
