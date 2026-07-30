import "package:flutter/foundation.dart";

class AppLifecycleService extends ChangeNotifier {
  AppLifecycleService._();

  static final AppLifecycleService instance = AppLifecycleService._();

  bool isForeground = true;

  void ensureStarted() {}
}