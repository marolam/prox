import "package:flutter/foundation.dart";

class CriticalUiService extends ChangeNotifier {
  CriticalUiService._();

  static final CriticalUiService instance = CriticalUiService._();

  bool isActive = false;

  void setActive(bool value) {
    isActive = value;
    notifyListeners();
  }
}