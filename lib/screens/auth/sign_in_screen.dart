import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/build_info_service.dart";
import "package:prox/services/secure_credential_store.dart";

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.credentialStore});
  final SecureCredentialStore? credentialStore;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();

  bool _busy = false;
  String? _error;

  bool _saveLogin = false;
  bool _saveAvailableLoaded = false;
  bool _deviceAuthenticationAvailable = false;
  bool _hasSavedLogin = false;
  SecureCredentialStore get _credentialStore =>
      widget.credentialStore ?? SecureCredentialStore.instance;

  @override
  void initState() {
    super.initState();
    _loadSaveToggle();
  }

  Future<void> _loadSaveToggle() async {
    try {
      final available = await _credentialStore.isAvailable();
      final enabled = await _credentialStore.isEnabled();
      final hasSaved =
          available && enabled && await _credentialStore.hasSavedCredentials();
      if (!mounted) return;
      setState(() {
        _saveLogin = enabled;
        _deviceAuthenticationAvailable = available;
        _hasSavedLogin = hasSaved;
        _saveAvailableLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveLogin = false;
        _deviceAuthenticationAvailable = false;
        _hasSavedLogin = false;
        _saveAvailableLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  bool get _hasEmail => _email.text.trim().isNotEmpty;
  bool get _hasPassword => _pass.text.isNotEmpty;
  bool get _canSignIn => !_busy && _hasEmail && _hasPassword;
  bool get _canCreateAccount => !_busy && _hasEmail && _pass.text.length >= 6;

  void _setError(String? msg) {
    if (!mounted) return;
    setState(() => _error = msg);
  }

  Future<void> _withBusy(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCredsBestEffort({
    required String email,
    required String password,
  }) async {
    bool saved = false;
    try {
      if (!_saveLogin) {
        await _credentialStore.setEnabled(false);
        return;
      }
      await _credentialStore.setEnabled(true);
      saved = await _credentialStore.writeCredentialsWithBiometrics(
        email: email,
        password: password,
        reason: "Confirm to save login on this device",
      );
    } catch (_) {
      // Optional device storage must never turn successful authentication into failure.
    }
    if (!mounted) return;
    await _loadSaveToggle();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? "Login saved on this device."
              : "Signed in. Login was not saved on this device.",
        ),
      ),
    );
  }

  Future<void> _changeSaveLogin(bool enabled) => _withBusy(() async {
    try {
      await _credentialStore.setEnabled(enabled);
      await _loadSaveToggle();
    } catch (_) {
      await _loadSaveToggle();
      _setError(
        "Could not change the saved-login setting. Device authentication and secure storage must be available.",
      );
    }
  });

  Future<void> _signIn() async {
    final em = _email.text.trim();
    final pw = _pass.text;

    await _withBusy(() async {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: em,
          password: pw,
        );

        await _saveCredsBestEffort(email: em, password: pw);

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Signed in.")));
      } on FirebaseAuthException catch (e) {
        _setError(e.message ?? "Authentication error.");
      } catch (_) {
        _setError("Unexpected sign-in error.");
      }
    });
  }

  Future<void> _signInWithSavedLogin() async {
    await _withBusy(() async {
      try {
        final credentials = await _credentialStore
            .readCredentialsWithBiometrics();
        if (!mounted) return;
        if (credentials == null) {
          await _loadSaveToggle();
          if (!_deviceAuthenticationAvailable) {
            _setError(
              "Device authentication is unavailable. Enter your email and password.",
            );
          }
          return;
        }
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: credentials["email"]!,
          password: credentials["password"]!,
        );
      } on FirebaseAuthException {
        _setError(
          "The saved login couldn't be used. Enter your current email and password.",
        );
      } catch (_) {
        _setError("Saved login is unavailable. Enter your email and password.");
      }
    });
  }

  Future<void> _createAccount() async {
    final em = _email.text.trim();
    final pw = _pass.text;

    await _withBusy(() async {
      try {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: em,
          password: pw,
        );

        await _saveCredsBestEffort(email: em, password: pw);

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Account created.")));
      } on FirebaseAuthException catch (e) {
        _setError(e.message ?? "Authentication error.");
      } catch (_) {
        _setError("Unexpected account creation error.");
      }
    });
  }

  Future<void> _sendResetEmail() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _setError(
        "Enter your email above first so we know where to send the reset link.",
      );
      return;
    }

    await _withBusy(() async {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Password reset email sent. Check your inbox."),
          ),
        );
      } on FirebaseAuthException catch (e) {
        _setError(e.message ?? "Could not send reset email.");
      } catch (_) {
        _setError("Unexpected reset email error.");
      }
    });
  }

  Future<void> _continueAsAnonymous() async {
    await _withBusy(() async {
      try {
        // Never abandon an existing guest identity to create a fresh account.
        if (FirebaseAuth.instance.currentUser != null) {
          _setError(
            "Sign out of your current account before creating a guest account.",
          );
          return;
        }
        await FirebaseAuth.instance.signInAnonymously();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Signed in as a guest. Keep this session to retain access to your guest account.",
            ),
          ),
        );
      } on FirebaseAuthException catch (e) {
        _setError(e.message ?? "Could not create an anonymous account.");
      } catch (_) {
        _setError("Unexpected anonymous sign-in error.");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final info = BuildInfoService.instance.info;
    final mode = const bool.fromEnvironment("PROX_TESTER", defaultValue: false)
        ? "tester"
        : "prod";

    return Scaffold(
      appBar: AppBar(title: const Text("Sign in")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  "Welcome back",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Connect with people nearby.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "build=${info.shortLabel} | mode=$mode",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _email,
                  focusNode: _emailFocus,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: "Email",
                    hintText: "you@example.com",
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pass,
                  focusNode: _passFocus,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: "Password"),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _canSignIn ? _signIn() : null,
                ),

                const SizedBox(height: 8),
                if (_saveAvailableLoaded)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _saveLogin,
                    onChanged: _busy || !_deviceAuthenticationAvailable
                        ? null
                        : _changeSaveLogin,
                    title: const Text("Save login on this device"),
                    subtitle: Text(
                      _deviceAuthenticationAvailable
                          ? "Protected by your device biometrics or passcode."
                          : "Device authentication is unavailable. Use email and password to sign in.",
                    ),
                  ),

                if (_saveAvailableLoaded && _hasSavedLogin)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _signInWithSavedLogin,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text("Use saved login"),
                  ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _sendResetEmail,
                    child: const Text("Forgot password?"),
                  ),
                ),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _canSignIn ? _signIn : null,
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text("Sign in"),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _canCreateAccount ? _createAccount : null,
                    child: const Text("Create account"),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _continueAsAnonymous,
                    icon: const Icon(Icons.person_outline),
                    label: const Text("Continue as guest"),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: cs.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
