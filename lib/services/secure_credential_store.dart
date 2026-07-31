class SecureCredentialStore {
  SecureCredentialStore._();
  static final SecureCredentialStore instance = SecureCredentialStore._();

  bool _enabled = false;
  String? _email;
  String? _password;

  Future<bool> isEnabled() async => _enabled;

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled) {
      _email = null;
      _password = null;
    }
  }

  Future<bool> writeCredentialsWithBiometrics({
    required String email,
    required String password,
    String? reason,
  }) async {
    if (!_enabled) return false;
    _email = email.trim();
    _password = password;
    return true;
  }

  Future<Map<String, String>?> readCredentialsWithBiometrics() async {
    if (!_enabled) return null;
    final e = _email;
    final p = _password;
    if ((e ?? "").isEmpty || (p ?? "").isEmpty) return null;
    return <String, String>{"email": e!, "password": p!};
  }

  Future<void> clearCredentials() async {
    _email = null;
    _password = null;
  }
}
