import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/material.dart";

/// Reports device connectivity without claiming an internet connection is healthy.
class ConnectivityStatusBanner extends StatefulWidget {
  const ConnectivityStatusBanner({super.key, required this.child});
  final Widget child;

  @override
  State<ConnectivityStatusBanner> createState() => _ConnectivityStatusBannerState();
}

class _ConnectivityStatusBannerState extends State<ConnectivityStatusBanner> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _offline = false;
  bool _receivedStreamEvent = false;

  @override
  void initState() {
    super.initState();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _receivedStreamEvent = true;
      _update(results);
    }, onError: (Object _) {});
    unawaited(_connectivity.checkConnectivity().then((results) {
      if (!_receivedStreamEvent) _update(results);
    }).catchError((Object _) {}));
  }

  void _update(List<ConnectivityResult> results) {
    if (!mounted) return;
    final offline = results.isNotEmpty &&
        results.every((result) => result == ConnectivityResult.none);
    if (offline != _offline) setState(() => _offline = offline);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    if (_offline)
      Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: SafeArea(bottom: false, child: Semantics(
          liveRegion: true,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(Icons.wifi_off, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text("You're offline. Recent information may be out of date.")),
            ]),
          ),
        )),
      ),
    Expanded(child: widget.child),
  ]);
}
