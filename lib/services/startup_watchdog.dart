class StartupWatchdog {
  StartupWatchdog._();

  static final StartupWatchdog instance = StartupWatchdog._();

  void arm() {}
  void disarm() {}
  void disarmAfterFirstFrame() {}
}