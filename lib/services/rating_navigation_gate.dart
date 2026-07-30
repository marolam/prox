class RatingNavigationGate {
  RatingNavigationGate._();
  static final RatingNavigationGate instance = RatingNavigationGate._();

  bool _allowNextOpen = false;

  // Arm immediately before explicit user-driven navigation to the rating UI.
  void armForNextOpen() {
    _allowNextOpen = true;
  }

  // Consume once so stale/restored routes cannot re-open rating on app relaunch.
  bool consumeIfArmed() {
    if (!_allowNextOpen) return false;
    _allowNextOpen = false;
    return true;
  }

  void disarm() {
    _allowNextOpen = false;
  }
}
