import "package:flutter/widgets.dart";

class ImeVisibilityService extends ChangeNotifier with WidgetsBindingObserver {
  ImeVisibilityService._();

  static final ImeVisibilityService instance = ImeVisibilityService._();

  bool _started = false;
  bool _isVisible = false;
  bool get isVisible => _isVisible;

  void ensureStarted() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    didChangeMetrics();
  }

  @override
  void didChangeMetrics() {
    final visible = WidgetsBinding.instance.platformDispatcher.views
        .any((view) => view.viewInsets.bottom > 0);
    if (visible == _isVisible) return;
    _isVisible = visible;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
    super.dispose();
  }
}
