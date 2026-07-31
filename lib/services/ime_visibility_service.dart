import "package:flutter/foundation.dart";

class ImeVisibilityService extends ChangeNotifier {
  ImeVisibilityService._();

  static final ImeVisibilityService instance = ImeVisibilityService._();

  bool isVisible = false;

  void ensureStarted() {}
}