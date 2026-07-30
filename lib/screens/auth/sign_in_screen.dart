import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";

import "package:prox/services/build_info_service.dart";
import "package:prox/services/secure_credential_store.dart";

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

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

  bool _saveLogin = true;
  bool _saveAvailableLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSaveToggle();
  }

  Future<void> _loadSaveToggle() async {
    try {
      final enabled = await SecureCredentialStore.instance.isEnabled();
      if (!mounted) return;
      setState(() {
        _saveLogin = enabled;
        _saveAvailableLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveLogin = true;
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

  Future<void> _saveCredsBestEffort({required String email, required String password}) async {
    if (!_saveLogin) {
      try { await SecureCredentialStore.instance.setEnabled(false); } catch (_) {}
      return;
    }

    try { await SecureCredentialStore.instance.setEnabled(true); } catch (_) {}

    final ok = await SecureCredentialStore.instance.writeCredentialsWithBiometrics(
      email: email,
      password: password,
      reason: "Confirm to save login on this device",
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "Login saved on this device." : "Signed in, but login was not saved.")),
    );
  }

  Future<void> _signIn() async {
    final em = _email.text.trim();
    final pw = _pass.text;

    await _withBusy(() async {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: em, password: pw);
        if (!mounted) return;

        await _saveCredsBestEffort(email: em, password: pw);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Signed in.")));
      } on FirebaseAuthException catch (e) {
        _setError(e.message ?? "Authentication error.");
      } catch (_) {
        _setError("Unexpected sign-in error.");
      }
    });
  }

  Future<void> _createAccount() async {
    final em = _email.text.trim();
    final pw = _pass.text;

    await _withBusy(() async {
      try {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: em, password: pw);
        if (!mounted) return;

        await _saveCredsBestEffort(email: em, password: pw);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account created.")));
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
      _setError("Enter your email above first so we know where to send the reset link.");
      return;
    }

    await _withBusy(() async {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password reset email sent. Check your inbox.")),
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
        // Ensure this creates a fresh anonymous auth session.
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      try {
        await FirebaseAuth.instance.signInAnonymously();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Signed in as a new anonymous user.")),
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
    final mode = const bool.fromEnvironment("PROX_TESTER", defaultValue: false) ? "tester" : "prod";

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
                Text("Welcome back", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("Password sign-in only.", style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text("build=${info.shortLabel} | mode=$mode", style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),

                TextField(
                  controller: _email,
                  focusNode: _emailFocus,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: "Email", hintText: "you@example.com"),
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
                    onChanged: _busy ? null : (v) async {
                      setState(() => _saveLogin = v);
                      try { await SecureCredentialStore.instance.setEnabled(v); } catch (_) {}
                    },
                    title: const Text("Save login on this device"),
                    subtitle: const Text("Uses biometrics/passcode when available."),
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
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                    label: const Text("Continue as new anonymous user"),
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
