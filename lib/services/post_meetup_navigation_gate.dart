class PostMeetupNavigationGate {
  PostMeetupNavigationGate._();
  static final PostMeetupNavigationGate instance =
      PostMeetupNavigationGate._();

  bool _allowNextOpen = false;

  // Arm immediately before explicit user-driven navigation to post-meetup flow.
  void armForNextOpen() {
    _allowNextOpen = true;
  }

  // Consume once so stale/restored routes cannot re-open post-meetup UI.
  bool consumeIfArmed() {
    if (!_allowNextOpen) return false;
    _allowNextOpen = false;
    return true;
  }

  void disarm() {
    _allowNextOpen = false;
  }
}
