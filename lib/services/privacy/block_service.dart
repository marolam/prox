import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Account-scoped, durable blocks shared by discovery, chat, and settings.
class BlockService extends ChangeNotifier {
  BlockService._();
  static final BlockService instance = BlockService._();

  final Set<String> _blocked = <String>{};
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _owner;
  Future<void>? _loading;
  Object? lastError;

  Set<String> get blockedUids => Set<String>.unmodifiable(_blocked);
  Future<void> get ready => ensureLoaded();

  Future<void> ensureLoaded() {
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (user?.uid != _owner) {
        unawaited(
          _load(user?.uid).catchError((Object error) {
            lastError = error;
            notifyListeners();
          }),
        );
      }
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_owner == uid && _loading != null) return _loading!;
    return _load(uid);
  }

  Future<void> _load(String? uid) {
    _owner = uid;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _blocked.clear();
    lastError = null;
    notifyListeners();
    if (uid == null) return _loading = Future<void>.value();
    final first = Completer<void>();
    _loading = first.future;
    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('blocks')
        .snapshots()
        .listen(
          (snapshot) {
            if (_owner != uid) return;
            _blocked
              ..clear()
              ..addAll(snapshot.docs.map((doc) => doc.id));
            lastError = null;
            if (!first.isCompleted) first.complete();
            notifyListeners();
          },
          onError: (Object error) {
            if (_owner != uid) return;
            lastError = error;
            if (!first.isCompleted) first.completeError(error);
            _loading = null;
            notifyListeners();
          },
        );
    return first.future;
  }

  bool isBlockedSync(String uid) {
    return _blocked.contains(uid.trim());
  }

  Future<void> block(String uid) async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    final clean = uid.trim();
    if (owner == null) throw StateError('Sign in to block a user.');
    if (clean.isEmpty || clean == owner || clean.contains('/')) {
      throw ArgumentError('Choose another valid user to block.');
    }
    await ensureLoaded();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(owner)
        .collection('blocks')
        .doc(clean)
        .set({'uid': clean, 'createdAt': FieldValue.serverTimestamp()});
    if (_owner == owner) {
      _blocked.add(clean);
      notifyListeners();
    }
  }

  Future<void> unblock(String uid) async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null) throw StateError('Sign in to unblock a user.');
    final clean = uid.trim();
    if (clean.isEmpty || clean.contains('/'))
      throw ArgumentError('Invalid user.');
    await FirebaseFirestore.instance
        .collection('users')
        .doc(owner)
        .collection('blocks')
        .doc(clean)
        .delete();
    if (_owner == owner) {
      _blocked.remove(clean);
      notifyListeners();
    }
  }
}
