import "package:flutter/foundation.dart";

class ContextHelpService {
  ContextHelpService._();
  static final ContextHelpService instance = ContextHelpService._();

  final ValueNotifier<String?> contextKey = ValueNotifier<String?>(null);

  void setContext(String? key) {
    final clean = key?.trim();
    contextKey.value = (clean == null || clean.isEmpty) ? null : clean;
  }
}
