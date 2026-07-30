import "package:flutter/foundation.dart";

class SupportModeService extends ChangeNotifier {
  SupportModeService._();
  static final SupportModeService instance = SupportModeService._();

  bool enabled = false;
  bool termsAccepted = false;

  void ensureLoaded() {}

  Future<void> acceptTerms() async {
    termsAccepted = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    notifyListeners();
  }
}
