import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prox/services/login_update_check_service.dart';

/// Lives inside MaterialApp.builder so the gate shares theme, text scale and
/// localization with the application. The child keeps its state while blocked.
class UpdateEnforcementGate extends StatefulWidget {
  const UpdateEnforcementGate({super.key, required this.child, this.service});
  final Widget child;
  final LoginUpdateCheckService? service;

  @override
  State<UpdateEnforcementGate> createState() => _UpdateEnforcementGateState();
}

class _UpdateEnforcementGateState extends State<UpdateEnforcementGate>
    with WidgetsBindingObserver {
  LoginUpdateCheckService get _service =>
      widget.service ?? LoginUpdateCheckService.instance;
  LoginUpdateCheckResult? _result;
  bool _checking = true;
  bool _refreshInFlight = false;
  bool _openingUpdateLink = false;
  String? _linkError;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _result = _service.latestResult.value;
    _service.latestResult.addListener(_receiveResult);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh(forceRefresh: true));
  }

  @override
  void dispose() {
    _service.latestResult.removeListener(_receiveResult);
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  void _receiveResult() {
    if (!mounted) return;
    setState(() => _result = _service.latestResult.value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh(forceRefresh: true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
    }
  }

  Future<void> _refresh({required bool forceRefresh}) async {
    if (!mounted || _refreshInFlight) return;
    _refreshInFlight = true;
    setState(() => _checking = true);
    try {
      final result = await _service.check(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (_) {
      // Retain a known required update if an unexpected platform failure occurs.
    } finally {
      _refreshInFlight = false;
      if (mounted) {
        setState(() => _checking = false);
        _pollTimer?.cancel();
        final minutes = _result == null || _result!.checkFailed
            ? 1
            : _result!.pollMinutes.clamp(5, 240);
        _pollTimer = Timer(Duration(minutes: minutes), () {
          unawaited(_refresh(forceRefresh: true));
        });
      }
    }
  }

  Future<void> _openUpdate() async {
    final result = _result;
    if (result == null || _openingUpdateLink) return;
    setState(() {
      _openingUpdateLink = true;
      _linkError = null;
    });
    try {
      final opened = await _service.openLatestUpdate(context,
          preferredUrl: result.downloadUrl,
          targetVersion: result.latestVersion);
      if (!opened && mounted) {
        setState(() => _linkError =
            "Couldn't open the update link. Check your connection and try again.");
      }
    } catch (_) {
      if (mounted)
        setState(() =>
            _linkError = "Couldn't open the update link. Please try again.");
    } finally {
      if (mounted) setState(() => _openingUpdateLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final initialLoading = _checking && result == null;
    final blocked = (result?.mustUpdateNow ?? false) || initialLoading;
    final theme = Theme.of(context);

    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: blocked,
            child: ExcludeFocus(
              excluding: blocked,
              child: IgnorePointer(
                ignoring: blocked,
                child: TickerMode(enabled: !blocked, child: widget.child),
              ),
            ),
          ),
          if (blocked) ...[
            const ModalBarrier(dismissible: false, color: Colors.black87),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Semantics(
                          scopesRoute: true,
                          explicitChildNodes: true,
                          namesRoute: true,
                          label: initialLoading
                              ? 'Checking app version'
                              : 'Update required',
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: initialLoading
                                ? [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 12),
                                    Text('Checking app version...',
                                        style: theme.textTheme.titleMedium),
                                  ]
                                : [
                                    Icon(Icons.system_update_alt_rounded,
                                        size: 42,
                                        color: theme.colorScheme.primary),
                                    const SizedBox(height: 12),
                                    Text('Update required',
                                        style: theme.textTheme.headlineSmall,
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Please install the required update before continuing.',
                                      textAlign: TextAlign.center,
                                    ),
                                    if (result!.minimumRequiredNotes
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text(result.minimumRequiredNotes,
                                          textAlign: TextAlign.center),
                                    ],
                                    const SizedBox(height: 12),
                                    Text(
                                      'Installed: v${result.currentVersion}\n'
                                      '${result.minimumRequiredVersion.isEmpty ? "" : "Minimum required: v${result.minimumRequiredVersion}\n"}'
                                      'Latest: v${result.latestVersion}',
                                      style: theme.textTheme.bodySmall,
                                      textAlign: TextAlign.center,
                                    ),
                                    if (result.checkFailed ||
                                        _linkError != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                          _linkError ??
                                              'You appear to be offline. The last required update still applies.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: theme.colorScheme.error)),
                                    ],
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _openingUpdateLink
                                            ? null
                                            : _openUpdate,
                                        icon: const Icon(Icons.open_in_new),
                                        label: Text(_openingUpdateLink
                                            ? 'Opening update link...'
                                            : 'Update now'),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: _checking
                                            ? null
                                            : () =>
                                                _refresh(forceRefresh: true),
                                        child: Text(_checking
                                            ? 'Checking...'
                                            : "I've updated, re-check"),
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
