import "dart:convert";
import "dart:typed_data";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:share_plus/share_plus.dart";
import "package:prox/services/account_deletion_service.dart";

class AccountPrivacyScreen extends StatefulWidget {
  const AccountPrivacyScreen({super.key});
  @override
  State<AccountPrivacyScreen> createState() => _AccountPrivacyScreenState();
}

class _AccountPrivacyScreenState extends State<AccountPrivacyScreen> {
  bool _busy = false;
  String? _error;
  bool _deletionConfirmed = false;
  String? _deletionUid;

  Future<void> _export(BuildContext originContext) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _busy) return;
    final box = originContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ref = FirebaseFirestore.instance.collection("users").doc(user.uid);
      final records = await Future.wait([
        ref.get(const GetOptions(source: Source.server)),
        ref
            .collection("meta")
            .doc("points")
            .get(const GetOptions(source: Source.server)),
        ref
            .collection("meta")
            .doc("policyAcks")
            .get(const GetOptions(source: Source.server)),
      ]).timeout(const Duration(seconds: 20));
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
      final document = {
        "exportedAt": DateTime.now().toUtc().toIso8601String(),
        "scope": "Account profile, points summary and policy acknowledgements",
        "account": {"uid": user.uid, "email": user.email},
        "profile": records[0].data(),
        "points": records[1].data(),
        "policyAcknowledgements": records[2].data(),
      };
      final json = const JsonEncoder.withIndent(
        "  ",
        _encodeFirestore,
      ).convert(document);
      if (!mounted) return;
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(json)),
            mimeType: "application/json",
            name: "prox-account.json",
          ),
        ],
        fileNameOverrides: ["prox-account.json"],
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              "Couldn't export your account summary. Check your connection and try again.",
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Object? _encodeFirestore(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is GeoPoint)
      return {"latitude": value.latitude, "longitude": value.longitude};
    if (value is DocumentReference) return value.path;
    throw FormatException("Unsupported account value");
  }

  Future<void> _confirmDeletion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _busy || _deletionConfirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final password = await showDialog<String>(
        context: context,
        builder: (_) => _DeletionConfirmationDialog(
          anonymous: user.isAnonymous,
          retrying: AccountDeletionService.instance.canRetryDeletion(user.uid),
        ),
      );
      if (password == null || !mounted) return;
      final result = await AccountDeletionService.instance.delete(
        expectedUid: user.uid,
        password: password,
      );
      if (!mounted) return;
      setState(() {
        _deletionConfirmed = true;
        _deletionUid = user.uid;
      });
      if (result.sessionChanged) {
        setState(
          () => _error =
              "The confirmed account was deleted. Your current account session was left unchanged.",
        );
      } else if (result.signOutPending) {
        setState(
          () => _error =
              "Your account was deleted, but this device could not finish signing out. Tap Finish signing out to retry.",
        );
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil("/auth", (_) => false);
      }
    } on AccountSessionChanged {
      if (mounted)
        setState(
          () => _error =
              "Your signed-in account changed. Open account settings again before confirming deletion.",
        );
    } on ArgumentError {
      if (mounted)
        setState(
          () => _error = "Enter your current password to confirm deletion.",
        );
    } on FirebaseAuthException catch (error) {
      if (mounted)
        setState(
          () => _error = error.code == "network-request-failed"
              ? "Check your connection and try again."
              : "We couldn't verify your password. Try again or reset it from the sign-in screen.",
        );
    } on FirebaseFunctionsException catch (error) {
      if (mounted)
        setState(
          () => _error = error.code == "failed-precondition"
              ? (error.message ??
                    "Your account needs attention before deletion. Contact support.")
              : "Account deletion wasn't confirmed. Check your connection and retry, or contact support.",
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              "Account deletion wasn't confirmed. Please retry or contact support.",
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishSignOut() async {
    if (_busy) return;
    final current = FirebaseAuth.instance.currentUser;
    if (current != null && current.uid != _deletionUid) {
      setState(
        () => _error =
            "The deleted account is no longer signed in. Your current account session was left unchanged.",
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted)
        Navigator.of(context).pushNamedAndRemoveUntil("/auth", (_) => false);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              "The account is deleted. This device still could not finish signing out; please retry.",
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Your account data")),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          "Save an account summary",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          "Download your profile, points summary and policy acknowledgements as JSON. For a full data request including conversations, contact Support & feedback.",
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (origin) => OutlinedButton.icon(
            onPressed: _busy || _deletionConfirmed
                ? null
                : () => _export(origin),
            icon: const Icon(Icons.download_outlined),
            label: const Text("Export account summary"),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          "Delete account",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          FirebaseAuth.instance.currentUser?.isAnonymous == true
              ? "Permanently remove this guest account and its associated data. Guest accounts do not have a password."
              : "Permanently remove your account. You will confirm your password before deletion starts.",
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : (_deletionConfirmed ? _finishSignOut : _confirmDeletion),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(
            _deletionConfirmed ? "Finish signing out" : "Delete my account",
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    ),
  );
}

class _DeletionConfirmationDialog extends StatefulWidget {
  const _DeletionConfirmationDialog({
    required this.anonymous,
    required this.retrying,
  });
  final bool anonymous;
  final bool retrying;
  @override
  State<_DeletionConfirmationDialog> createState() =>
      _DeletionConfirmationDialogState();
}

class _DeletionConfirmationDialogState
    extends State<_DeletionConfirmationDialog> {
  final _password = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.retrying
          ? "Retry account deletion?"
          : widget.anonymous
          ? "Delete this guest account?"
          : "Delete your Prox account?",
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "This permanently deletes this account and associated Prox data. It cannot be undone.",
          ),
          if (widget.retrying) ...[
            const SizedBox(height: 12),
            const Text(
              "Your previous request has not been confirmed. Retry it using the same recently verified account session.",
            ),
          ],
          if (!widget.anonymous && !widget.retrying) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: "Confirm your password",
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.retrying ? "Close" : "Keep account"),
      ),
      FilledButton(
        onPressed:
            widget.anonymous || widget.retrying || _password.text.isNotEmpty
            ? () => Navigator.pop(context, _password.text)
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        child: const Text("Delete account"),
      ),
    ],
  );
}
