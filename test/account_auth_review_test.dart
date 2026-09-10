import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/secure_credential_store.dart';
import 'package:prox/services/account_deletion_service.dart';
import 'package:prox/screens/auth/sign_in_screen.dart';

class _Vault {
  final values = <String, String>{};
  bool supported = true;
  bool unlockResult = true;
  bool failWrites = false;
  bool failDeletes = false;
  int unlocks = 0;
  Completer<bool>? unlockGate;
  final prompted = Completer<void>();
  late final service = SecureCredentialStore.forTesting(
    read: (key) async => values[key],
    write: (key, value) async {
      if (failWrites) throw StateError('write failed');
      values[key] = value;
    },
    delete: (key) async {
      if (failDeletes) throw StateError('delete failed');
      values.remove(key);
    },
    supported: () async => supported,
    authenticate: (_) async {
      unlocks++;
      if (!prompted.isCompleted) prompted.complete();
      return unlockGate == null ? unlockResult : await unlockGate!.future;
    },
  );
  void seed() {
    values['prox_saved_login_enabled'] = 'true';
    values['prox_saved_login'] = jsonEncode({
      'email': 'person@example.com',
      'password': 'test-password',
    });
  }
}

class _DeletionHarness {
  DeletionIdentity? identity = const DeletionIdentity(
    uid: 'alice',
    anonymous: false,
    email: 'alice@example.com',
  );
  final events = <String>[];
  final requestedUids = <String>[];
  void Function()? afterReauthentication;
  void Function()? afterRemote;
  bool remoteConfirmed = true;
  bool cleanupFails = false;
  bool signOutFails = false;
  DateTime now = DateTime.utc(2026, 9, 8);
  late final service = AccountDeletionService(
    currentIdentity: () => identity,
    reauthenticate: (_, _) async {
      events.add('reauth');
      afterReauthentication?.call();
    },
    refreshToken: () async {
      events.add('token');
    },
    deleteRemote: (uid) async {
      requestedUids.add(uid);
      events.add('delete');
      afterRemote?.call();
      return remoteConfirmed;
    },
    clearAccountQueue: (uid) async {
      events.add('queue:$uid');
      if (cleanupFails) throw StateError('cleanup');
    },
    sessionCleanup: [
      (uid) async {
        events.add('session:$uid');
      },
    ],
    signOut: () async {
      events.add('signout');
      if (signOutFails) throw StateError('signout');
      identity = null;
    },
    clock: () => now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'clearing credentials during an OS unlock prevents a late password write',
    () async {
      final vault = _Vault()..unlockGate = Completer<bool>();
      await vault.service.setEnabled(true);
      final save = vault.service.writeCredentialsWithBiometrics(
        email: 'alice@example.com',
        password: 'private',
      );
      await vault.prompted.future;
      await vault.service.clearCredentials();
      vault.unlockGate!.complete(true);
      expect(await save, isFalse);
      expect(vault.values.containsKey('prox_saved_login'), isFalse);
      expect(await vault.service.isEnabled(), isFalse);
    },
  );

  test(
    'clearing credentials during unlock cannot return a stale saved password',
    () async {
      final vault = _Vault()
        ..seed()
        ..unlockGate = Completer<bool>();
      final read = vault.service.readCredentialsWithBiometrics();
      await vault.prompted.future;
      await vault.service.clearCredentials();
      vault.unlockGate!.complete(true);
      expect(await read, isNull);
    },
  );

  test('a session transition invalidates an in-flight saved login', () async {
    final vault = _Vault()
      ..seed()
      ..unlockGate = Completer<bool>();
    final read = vault.service.readCredentialsWithBiometrics();
    await vault.prompted.future;
    vault.service.invalidatePendingOperations();
    vault.unlockGate!.complete(true);
    expect(await read, isNull);
    expect(await vault.service.hasSavedCredentials(), isTrue);
  });

  test(
    'canceled save and missing credentials do not advertise a saved login',
    () async {
      final vault = _Vault()..unlockResult = false;
      await vault.service.setEnabled(true);
      expect(
        await vault.service.writeCredentialsWithBiometrics(
          email: 'alice@example.com',
          password: 'private',
        ),
        isFalse,
      );
      expect(await vault.service.hasSavedCredentials(), isFalse);
      expect(await vault.service.readCredentialsWithBiometrics(), isNull);
      expect(vault.unlocks, 1);
    },
  );

  test('failed credential deletion still disables access', () async {
    final vault = _Vault()
      ..seed()
      ..failDeletes = true;
    await expectLater(vault.service.clearCredentials(), throwsStateError);
    expect(vault.values['prox_saved_login_enabled'], 'false');
    expect(await vault.service.isEnabled(), isFalse);
    expect(await vault.service.readCredentialsWithBiometrics(), isNull);
  });

  test(
    'failed disable flag still attempts to delete the encrypted password',
    () async {
      final vault = _Vault()
        ..seed()
        ..failWrites = true;
      await expectLater(vault.service.clearCredentials(), throwsStateError);
      expect(vault.values.containsKey('prox_saved_login'), isFalse);
      expect(await vault.service.isEnabled(), isFalse);
    },
  );

  testWidgets(
    'unsupported devices explain saved login availability and keep password sign-in',
    (tester) async {
      final vault = _Vault()..supported = false;
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen(credentialStore: vault.service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Use saved login'), findsNothing);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(
        find.textContaining('Device authentication is unavailable'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNWidgets(2));
    },
  );

  testWidgets(
    'enabled preference without saved credentials has no dead login button',
    (tester) async {
      final vault = _Vault();
      vault.values['prox_saved_login_enabled'] = 'true';
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen(credentialStore: vault.service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Use saved login'), findsNothing);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    },
  );

  test(
    'anonymous deletion uses existing identity without requesting a password',
    () async {
      final h = _DeletionHarness()
        ..identity = const DeletionIdentity(uid: 'guest', anonymous: true);
      final result = await h.service.delete(expectedUid: 'guest');
      expect(h.events, [
        'token',
        'delete',
        'queue:guest',
        'session:guest',
        'signout',
      ]);
      expect(result.signOutPending, isFalse);
      expect(h.requestedUids, ['guest']);
    },
  );

  test(
    'registered account needs a password before any deletion call',
    () async {
      final h = _DeletionHarness();
      await expectLater(
        h.service.delete(expectedUid: 'alice'),
        throwsArgumentError,
      );
      expect(h.events, isEmpty);
    },
  );

  test(
    'stale deletion dialog never starts a request for another account',
    () async {
      final h = _DeletionHarness();
      await expectLater(
        h.service.delete(expectedUid: 'someone-else', password: 'test'),
        throwsA(isA<AccountSessionChanged>()),
      );
      expect(h.events, isEmpty);
    },
  );

  test(
    'account switch during reauthentication stops deletion before the callable',
    () async {
      final h = _DeletionHarness();
      h.afterReauthentication = () =>
          h.identity = const DeletionIdentity(uid: 'bob', anonymous: true);
      await expectLater(
        h.service.delete(expectedUid: 'alice', password: 'test'),
        throwsA(isA<AccountSessionChanged>()),
      );
      expect(h.events, ['reauth']);
    },
  );

  test(
    'account switch after confirmed deletion does not clear or sign out the new session',
    () async {
      final h = _DeletionHarness();
      h.afterRemote = () =>
          h.identity = const DeletionIdentity(uid: 'bob', anonymous: true);
      final result = await h.service.delete(
        expectedUid: 'alice',
        password: 'test',
      );
      expect(result.sessionChanged, isTrue);
      expect(h.events, ['reauth', 'token', 'delete', 'queue:alice']);
      expect(h.identity?.uid, 'bob');
    },
  );

  test(
    'unconfirmed remote deletion does not clean local data or sign out',
    () async {
      final h = _DeletionHarness()..remoteConfirmed = false;
      await expectLater(
        h.service.delete(expectedUid: 'alice', password: 'test'),
        throwsStateError,
      );
      expect(h.events, ['reauth', 'token', 'delete']);
    },
  );

  test(
    'confirmed deletion remains confirmed when local cleanup or signout fails',
    () async {
      final h = _DeletionHarness()
        ..cleanupFails = true
        ..signOutFails = true;
      final result = await h.service.delete(
        expectedUid: 'alice',
        password: 'test',
      );
      expect(result.localCleanupFailed, isTrue);
      expect(result.signOutPending, isTrue);
      expect(h.events, [
        'reauth',
        'token',
        'delete',
        'queue:alice',
        'session:alice',
        'signout',
      ]);
    },
  );

  test(
    'lost deletion response can retry the same verified account without forcing a new token',
    () async {
      final h = _DeletionHarness();
      h.afterRemote = () => throw TimeoutException('confirmation lost');
      await expectLater(
        h.service.delete(expectedUid: 'alice', password: 'test'),
        throwsA(isA<TimeoutException>()),
      );
      expect(h.service.canRetryDeletion('alice'), isTrue);
      h.afterRemote = null;
      final result = await h.service.delete(expectedUid: 'alice');
      expect(result.signOutPending, isFalse);
      expect(h.events.where((event) => event == 'reauth'), hasLength(1));
      expect(h.events.where((event) => event == 'token'), hasLength(1));
      expect(h.requestedUids, ['alice', 'alice']);
    },
  );

  test(
    'deletion retry authentication expires and is bound to the confirmed identity',
    () async {
      final h = _DeletionHarness()..remoteConfirmed = false;
      await expectLater(
        h.service.delete(expectedUid: 'alice', password: 'test'),
        throwsStateError,
      );
      h.identity = const DeletionIdentity(uid: 'bob', anonymous: true);
      expect(h.service.canRetryDeletion('alice'), isFalse);
      expect(h.service.canRetryDeletion('bob'), isFalse);
      h.identity = const DeletionIdentity(
        uid: 'alice',
        anonymous: false,
        email: 'alice@example.com',
      );
      h.now = h.now.add(const Duration(minutes: 4));
      expect(h.service.canRetryDeletion('alice'), isFalse);
      await expectLater(
        h.service.delete(expectedUid: 'alice'),
        throwsArgumentError,
      );
      expect(h.requestedUids, ['alice']);
    },
  );
}
