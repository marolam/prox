import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/services/privacy/block_service.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _service = BlockService.instance;
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.ensureLoaded().timeout(const Duration(seconds: 12));
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not load blocked users. Check your connection and retry.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock this account?'),
        content: const Text(
          'This account may appear in discovery and contact you again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(uid));
    try {
      await _service.unblock(uid).timeout(const Duration(seconds: 15));
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Account unblocked.')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not confirm the change. Reconnect and retry.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Blocked users')),
    body: AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        if (FirebaseAuth.instance.currentUser == null)
          return const Center(
            child: Text('Sign in to manage blocked accounts.'),
          );
        if (_loading) return const Center(child: CircularProgressIndicator());
        if (_error != null || _service.lastError != null)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error ?? 'Blocked users could not be refreshed.'),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          );
        final users = _service.blockedUids.toList()..sort();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Blocks are saved to your account and apply across your signed-in devices. Unblocking allows the account to appear again.',
            ),
            const SizedBox(height: 16),
            if (users.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'You have no blocked accounts. Use Block from a person’s profile or conversation when you need it.',
                  ),
                ),
              ),
            for (final uid in users)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('Blocked account'),
                  subtitle: Text(
                    uid,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: _busy.contains(uid) ? null : () => _unblock(uid),
                    child: Text(_busy.contains(uid) ? 'Updating…' : 'Unblock'),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
