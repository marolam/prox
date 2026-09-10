import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SecureCredentialStore {
  SecureCredentialStore._({
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
    Future<void> Function(String)? delete,
    Future<bool> Function()? supported,
    Future<bool> Function(String)? authenticate,
  }) : _read = read ?? ((key) => _nativeStorage.read(key: key)),
       _write =
           write ??
           ((key, value) => _nativeStorage.write(key: key, value: value)),
       _delete = delete ?? ((key) => _nativeStorage.delete(key: key)),
       _supported = supported ?? _nativeAuth.isDeviceSupported,
       _unlock =
           authenticate ??
           ((reason) => _nativeAuth.authenticate(
             localizedReason: reason,
             options: const AuthenticationOptions(
               biometricOnly: false,
               stickyAuth: true,
             ),
           ));

  @visibleForTesting
  factory SecureCredentialStore.forTesting({
    required Future<String?> Function(String) read,
    required Future<void> Function(String, String) write,
    required Future<void> Function(String) delete,
    required Future<bool> Function() supported,
    required Future<bool> Function(String) authenticate,
  }) => SecureCredentialStore._(
    read: read,
    write: write,
    delete: delete,
    supported: supported,
    authenticate: authenticate,
  );

  static final SecureCredentialStore instance = SecureCredentialStore._();
  static const _enabledKey = 'prox_saved_login_enabled';
  static const _credentialsKey = 'prox_saved_login';
  static const _nativeStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  static final _nativeAuth = LocalAuthentication();
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<void> Function(String) _delete;
  final Future<bool> Function() _supported;
  final Future<bool> Function(String) _unlock;
  Future<void> _pendingMutation = Future.value();
  bool _authenticating = false;
  bool _disabledInSession = false;
  int _revision = 0;

  Future<bool> isAvailable() async {
    try {
      return await _supported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    if (_disabledInSession) return false;
    final revision = _revision;
    final value = await _read(_enabledKey);
    return !_disabledInSession && revision == _revision && value == 'true';
  }

  Future<bool> hasSavedCredentials() async {
    if (!await isEnabled()) return false;
    final revision = _revision;
    final raw = await _read(_credentialsKey);
    return revision == _revision && !_disabledInSession && _decode(raw) != null;
  }

  Future<void> _mutate(Future<void> Function() action) {
    final operation = _pendingMutation.then((_) => action());
    _pendingMutation = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!enabled) return clearCredentials();
    final revision = ++_revision;
    if (!await isAvailable())
      throw UnsupportedError('Device authentication is unavailable.');
    await _mutate(() async {
      if (revision != _revision) return;
      await _write(_enabledKey, 'true');
      if (revision == _revision) _disabledInSession = false;
    });
  }

  Future<bool> writeCredentialsWithBiometrics({
    required String email,
    required String password,
    String? reason,
  }) async {
    final revision = _revision;
    if (email.trim().isEmpty || password.isEmpty || !await isEnabled())
      return false;
    if (revision != _revision ||
        !await _authenticate(reason ?? 'Confirm to save your Prox login'))
      return false;
    if (revision != _revision || _disabledInSession) return false;
    var saved = false;
    await _mutate(() async {
      if (revision != _revision || _disabledInSession) return;
      await _write(
        _credentialsKey,
        jsonEncode({'email': email.trim(), 'password': password}),
      );
      saved = revision == _revision && !_disabledInSession;
    });
    return saved;
  }

  Future<Map<String, String>?> readCredentialsWithBiometrics() async {
    final revision = _revision;
    if (!await isEnabled()) return null;
    // Do not prompt the user for a saved-login entry that does not exist.
    if (!await hasSavedCredentials() || revision != _revision) return null;
    if (!await _authenticate('Unlock your saved Prox login')) return null;
    if (revision != _revision || _disabledInSession) return null;
    final raw = await _read(_credentialsKey);
    if (revision != _revision || _disabledInSession) return null;
    return _decode(raw);
  }

  static Map<String, String>? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['email'] is! String ||
          data['password'] is! String)
        return null;
      final email = (data['email'] as String).trim();
      final password = data['password'] as String;
      if (email.isEmpty || password.isEmpty) return null;
      return {'email': email, 'password': password};
    } on FormatException {
      return null;
    }
  }

  Future<void> clearCredentials() {
    ++_revision;
    _disabledInSession = true;
    return _mutate(() async {
      Object? error;
      // Disable access even if deleting the encrypted value encounters a storage error.
      try {
        await _write(_enabledKey, 'false');
      } catch (e) {
        error = e;
      }
      try {
        await _delete(_credentialsKey);
      } catch (e) {
        error ??= e;
      }
      if (error != null) throw error;
    });
  }

  /// Invalidates an in-flight unlock without removing an already saved login.
  void invalidatePendingOperations() {
    ++_revision;
  }

  Future<bool> _authenticate(String reason) async {
    if (_authenticating) return false;
    _authenticating = true;
    try {
      if (!await isAvailable()) return false;
      return await _unlock(reason);
    } catch (_) {
      return false;
    } finally {
      _authenticating = false;
    }
  }
}
