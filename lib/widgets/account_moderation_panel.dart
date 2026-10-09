import 'dart:math';
import 'package:flutter/material.dart';
import 'package:prox/services/auth/authenticated_callable.dart';

typedef AccountModerationCaller =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

class AccountModerationPanel extends StatefulWidget {
  const AccountModerationPanel({super.key, required this.ownerUid, this.call});
  final String ownerUid;
  final AccountModerationCaller? call;

  @override
  State<AccountModerationPanel> createState() => _AccountModerationPanelState();
}

class _AccountModerationPanelState extends State<AccountModerationPanel> {
  final _target = TextEditingController();
  final _reason = TextEditingController();
  final _confirmation = TextEditingController();
  String _action = 'suspend';
  String? _error;
  String? _result;
  Map<String, dynamic>? _pending;
  bool _busy = false;

  Future<void> _loadPending() async {
    if (_busy || _target.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = (await callAuthenticatedFunction<Map<String, dynamic>>(
        'getAccountModerationStatus',
        {'expectedUid': widget.ownerUid, 'targetUid': _target.text.trim()},
      )).data;
      final pending = result['pending'];
      if (pending != null && pending is! Map)
        throw StateError('Invalid pending moderation response.');
      if (!mounted) return;
      setState(() {
        _pending = pending == null ? null : Map<String, dynamic>.from(pending);
        if (_pending != null) {
          _action = _pending!['action'] as String;
          _reason.text = _pending!['reason'] as String;
          _confirmation.text = _target.text.trim();
          _result =
              'Recovered ${result['phase']} action. Retry uses its original request ID.';
        } else {
          _result =
              'No pending action. Enforcement status: ${result['status']}.';
        }
      });
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Could not load moderation status: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _reason.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final target = _target.text.trim();
    if (_pending == null &&
        (target.isEmpty ||
            target == widget.ownerUid ||
            target.contains('/') ||
            _reason.text.trim().length < 8 ||
            (_action == 'delete' && _confirmation.text.trim() != target))) {
      setState(
        () => _error =
            'Enter a different user UID and a detailed reason. For deletion, type their exact UID again.',
      );
      return;
    }
    if (_pending == null) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Confirm $_action'),
          content: Text(
            _action == 'delete'
                ? 'Permanently delete $target and their account data? This cannot be undone. The moderation audit is retained.'
                : '${_action == 'suspend' ? 'Immediately restrict' : 'Restore access for'} $target?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (!mounted || approved != true) return;
      _pending = {
        'expectedUid': widget.ownerUid,
        'targetUid': target,
        'action': _action,
        'reason': _reason.text.trim(),
        'requestId':
            'moderation_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
      };
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final payload = Map<String, dynamic>.from(_pending!);
      final result = widget.call != null
          ? await widget.call!(payload)
          : (await callAuthenticatedFunction<Map<String, dynamic>>(
              'moderateAccount',
              payload,
              timeout: const Duration(minutes: 9),
            )).data;
      final expectedStatus = {
        'suspend': 'suspended',
        'restore': 'active',
        'delete': 'deleted',
      }[payload['action']];
      if (result['status'] != expectedStatus)
        throw StateError(
          'Moderation completion was not verified. Retry the same request.',
        );
      if (!mounted) return;
      setState(() {
        _result = 'Verified: ${payload['targetUid']} is ${result['status']}.';
        _pending = null;
      });
    } catch (error) {
      if (mounted)
        setState(
          () => _error =
              '$error\nRetry keeps the same request ID; do not assume this action completed.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = !_busy && _pending == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Account moderation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Administrator-only controls. Suspend first to stop access while investigating. '
            'Deletion is permanent; suspension can be appealed through support.',
          ),
          TextField(
            controller: _target,
            enabled: editable,
            decoration: const InputDecoration(labelText: 'Target user UID'),
          ),
          TextButton(
            onPressed: editable ? _loadPending : null,
            child: const Text('Load status / recover pending action'),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(_action),
            initialValue: _action,
            items: const [
              DropdownMenuItem(
                value: 'suspend',
                child: Text('Suspend immediately'),
              ),
              DropdownMenuItem(value: 'restore', child: Text('Restore access')),
              DropdownMenuItem(
                value: 'delete',
                child: Text('Permanently delete'),
              ),
            ],
            onChanged: editable
                ? (value) => setState(() => _action = value!)
                : null,
          ),
          TextField(
            controller: _reason,
            enabled: editable,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Moderation reason / evidence reference',
            ),
          ),
          if (_action == 'delete')
            TextField(
              controller: _confirmation,
              enabled: editable,
              decoration: const InputDecoration(
                labelText: 'Type exact target UID to confirm deletion',
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_result != null) Text(_result!),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy
                  ? 'Applying...'
                  : _pending != null
                  ? 'Retry same action'
                  : 'Review action',
            ),
          ),
        ],
      ),
    );
  }
}
