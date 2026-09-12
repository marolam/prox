import "package:flutter/widgets.dart";

class AppLifecycleService extends ChangeNotifier with WidgetsBindingObserver {
  AppLifecycleService._();

  static final AppLifecycleService instance = AppLifecycleService._();

  bool _started = false;
  bool _isForeground = true;
  bool get isForeground => _isForeground;

  void ensureStarted() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    didChangeAppLifecycleState(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final next = state == AppLifecycleState.resumed;
    if (next == _isForeground) return;
    _isForeground = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
    super.dispose();
  }
}
