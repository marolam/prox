import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prox/services/auth/auth_bootstrap.dart';
import 'package:prox/services/offline/offline_outbox_service.dart';
import 'package:prox/services/push_notifications.dart';
import 'package:prox/services/secure_credential_store.dart';
import 'package:prox/services/action_receipt_service.dart';
import 'package:prox/services/support_ticket_queue.dart';
import 'package:prox/services/user_settings_service.dart';

class DeletionIdentity {
  const DeletionIdentity({
    required this.uid,
    required this.anonymous,
    this.email,
  });
  final String uid;
  final bool anonymous;
  final String? email;
}

class AccountSessionChanged implements Exception {}

class AccountDeletionResult {
  const AccountDeletionResult({
    this.sessionChanged = false,
    this.signOutPending = false,
    this.localCleanupFailed = false,
  });
  final bool sessionChanged;
  final bool signOutPending;
  final bool localCleanupFailed;
}

/// Keeps authentication and irreversible deletion tied to the identity confirmed
/// in the dialog, even when session changes occur during an awaited operation.
class AccountDeletionService {
  AccountDeletionService({
    required this.currentIdentity,
    required this.reauthenticate,
    required this.refreshToken,
    required this.deleteRemote,
    required this.clearAccountQueue,
    required this.sessionCleanup,
    required this.signOut,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DeletionIdentity? Function() currentIdentity;
  final Future<void> Function(String email, String password) reauthenticate;
  final Future<void> Function() refreshToken;
  final Future<bool> Function(String expectedUid) deleteRemote;
  final Future<void> Function(String uid) clearAccountQueue;
  final List<Future<void> Function(String uid)> sessionCleanup;
  final Future<void> Function() signOut;
  final DateTime Function() _clock;
  String? _pendingUid;
  DateTime? _verifiedAt;

  /// Reuse the already verified token after an uncertain response. Forcing a
  /// refresh here could discard a valid token after the server removed the Auth
  /// user but before the confirmation reached this device.
  bool canRetryDeletion(String uid) {
    final verifiedAt = _verifiedAt;
    if (_pendingUid != uid ||
        verifiedAt == null ||
        currentIdentity()?.uid != uid)
      return false;
    final age = _clock().difference(verifiedAt);
    return !age.isNegative && age < const Duration(minutes: 4);
  }

  static final instance = AccountDeletionService(
    currentIdentity: () {
      final user = FirebaseAuth.instance.currentUser;
      return user == null
          ? null
          : DeletionIdentity(
              uid: user.uid,
              anonymous: user.isAnonymous,
              email: user.email,
            );
    },
    reauthenticate: (email, password) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw AccountSessionChanged();
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    },
    refreshToken: () async {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    },
    deleteRemote: (expectedUid) async {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
            'deleteMyAccount',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
          )
          .call<dynamic>({'expectedUid': expectedUid});
      return result.data is Map && result.data['deleted'] == true;
    },
    clearAccountQueue: (uid) async {
      await Future.wait([
        OfflineOutboxService.instance.clearForUser(uid),
        SupportTicketQueue.instance.clearForUser(uid),
        ActionReceiptService.instance.clearForUser(uid),
        _clearAccountPreferences(uid),
      ]);
    },
    sessionCleanup: [
      (_) => AuthBootstrap.instance.prepareForManualSignOut(),
      (uid) => PushNotifications.instance.signOutCleanup(uid),
      (_) => SecureCredentialStore.instance.clearCredentials(),
      (_) => UserSettingsService.instance.resetAfterAccountDeletion(),
    ],
    signOut: () => FirebaseAuth.instance.signOut(),
  );

  static Future<void> _clearAccountPreferences(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in [
      'report.draft.incidents.$uid',
      'report.draft.bugReports.$uid',
      'checklist.v1.presence.$uid',
    ]) {
      if (!await preferences.remove(key))
        throw StateError('Could not remove account preferences');
    }
  }

  void _requireSameAccount(String uid) {
    if (currentIdentity()?.uid != uid) throw AccountSessionChanged();
  }

  Future<AccountDeletionResult> delete({
    required String expectedUid,
    String password = '',
  }) async {
    _requireSameAccount(expectedUid);
    final identity = currentIdentity()!;
    final retrying = canRetryDeletion(expectedUid);
    if (!retrying && !identity.anonymous) {
      if (identity.email == null || password.isEmpty) {
        throw ArgumentError('Enter your password to confirm account deletion.');
      }
      await reauthenticate(identity.email!, password);
      _requireSameAccount(expectedUid);
    }
    // Guests have no password/provider credential to reauthenticate with. The
    // callable accepts their existing authenticated identity for deletion.
    if (!retrying) {
      await refreshToken();
      _verifiedAt = _clock();
    }
    _requireSameAccount(expectedUid);
    _pendingUid = expectedUid;
    if (!await deleteRemote(expectedUid))
      throw StateError('Deletion has not been confirmed');
    _pendingUid = null;
    _verifiedAt = null;

    // Once confirmed, a cleanup error must not be presented as failed deletion.
    var cleanupFailed = false;
    try {
      await clearAccountQueue(expectedUid);
    } catch (_) {
      cleanupFailed = true;
    }
    for (final cleanup in sessionCleanup) {
      if (currentIdentity()?.uid != expectedUid) {
        return AccountDeletionResult(
          sessionChanged: true,
          localCleanupFailed: cleanupFailed,
        );
      }
      try {
        await cleanup(expectedUid);
      } catch (_) {
        cleanupFailed = true;
      }
    }
    if (currentIdentity()?.uid != expectedUid) {
      return AccountDeletionResult(
        sessionChanged: true,
        localCleanupFailed: cleanupFailed,
      );
    }
    try {
      await signOut();
      return AccountDeletionResult(localCleanupFailed: cleanupFailed);
    } catch (_) {
      return AccountDeletionResult(
        signOutPending: true,
        localCleanupFailed: cleanupFailed,
      );
    }
  }
}
