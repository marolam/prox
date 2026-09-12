import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/services/runtime_diagnostics_service.dart';
import 'package:prox/services/user_settings_service.dart';

/// Keeps active matching controls in step with server grants and revocations.
/// The stream and identity providers are injectable without initializing Firebase.
class BillingEntitlementSyncService {
  BillingEntitlementSyncService({
    required this.currentUid,
    required this.watchEntitlements,
    required this.settings,
    this.onError,
  });

  final String? Function() currentUid;
  final Stream<Map<String, dynamic>?> Function(String uid) watchEntitlements;
  final UserSettingsService settings;
  final void Function(Object error, StackTrace stack)? onError;
  StreamSubscription<Map<String, dynamic>?>? _subscription;
  String? _uid;
  int _generation = 0;
  bool _bound = false;

  static final instance = BillingEntitlementSyncService(
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    watchEntitlements: (uid) => FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('billing')
        .doc('entitlements')
        .snapshots(includeMetadataChanges: true)
        // Old offline cache entries and local pending writes cannot restore a
        // refunded grant. Wait for a server-confirmed snapshot after sign-in.
        .where(
          (snapshot) =>
              !snapshot.metadata.isFromCache &&
              !snapshot.metadata.hasPendingWrites,
        )
        .map((snapshot) => snapshot.data()),
    settings: UserSettingsService.instance,
    onError: (error, stack) => RuntimeDiagnosticsService.instance.record(
      error,
      stack,
      operation: 'Paid access synchronization',
    ),
  );

  bool _isCurrent(int generation, String? uid) =>
      generation == _generation && uid == _uid && currentUid() == uid;

  Future<void> bindAccount(String? uid) {
    if (_bound && _uid == uid) return Future<void>.value();
    _bound = true;
    _uid = uid;
    final generation = ++_generation;
    final previous = _subscription;
    _subscription = null;
    if (previous != null)
      unawaited(previous.cancel().catchError((Object _) {}));
    final reset = settings.bindAccountSession(uid);
    if (uid != null && _isCurrent(generation, uid)) {
      void fail(Object error, StackTrace stack) {
        if (!_isCurrent(generation, uid)) return;
        settings.applyBillingEntitlements(uid, null);
        onError?.call(error, stack);
      }

      try {
        _subscription = watchEntitlements(uid).listen(
          (data) {
            if (_isCurrent(generation, uid))
              settings.applyBillingEntitlements(uid, data);
          },
          onError: fail,
          onDone: () {
            if (_isCurrent(generation, uid))
              settings.applyBillingEntitlements(uid, null);
          },
        );
      } catch (error, stack) {
        fail(error, stack);
      }
    }
    return reset.catchError((Object error, StackTrace stack) {
      if (_isCurrent(generation, uid)) onError?.call(error, stack);
    });
  }

  Future<void> dispose() async {
    ++_generation;
    _bound = false;
    _uid = null;
    final previous = _subscription;
    _subscription = null;
    await previous?.cancel();
  }
}
