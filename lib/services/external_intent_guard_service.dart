class ExternalIntentGuardService {
  ExternalIntentGuardService._();

  static final ExternalIntentGuardService instance =
      ExternalIntentGuardService._();

  DateTime? _lastIntentOpenedAt;

  void markIntentOpened() {
    _lastIntentOpenedAt = DateTime.now();
  }

  bool openedRecently(Duration window) {
    final at = _lastIntentOpenedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) <= window;
  }
}
