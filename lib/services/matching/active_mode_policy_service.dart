class ActiveModePolicyService {
  ActiveModePolicyService._();
  static final ActiveModePolicyService instance = ActiveModePolicyService._();

  bool _lockedByBackend = false;

  bool get isLockedByBackend => _lockedByBackend;

  void ensureWatching() {
    // No-op fallback in this branch.
  }

  void setLockedByBackend(bool value) {
    _lockedByBackend = value;
  }

  Future<void> evaluateAndApplyPenaltyIfNeeded() async {}
}
