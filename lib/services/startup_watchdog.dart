import "dart:async";

import "package:flutter/widgets.dart";

class StartupWatchdog {
  StartupWatchdog._();

  static final StartupWatchdog instance = StartupWatchdog._();

  Timer? _timer;
  final Stopwatch _elapsed = Stopwatch();
  Duration? firstFrameElapsed;

  void arm() {
    _timer?.cancel();
    _elapsed..reset()..start();
    firstFrameElapsed = null;
    _timer = Timer(const Duration(seconds: 15), () {
      debugPrint("[Startup] First frame has not arrived after 15 seconds.");
    });
  }

  void disarm() {
    _timer?.cancel();
    _timer = null;
  }

  void disarmAfterFirstFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      firstFrameElapsed ??= _elapsed.elapsed;
      _elapsed.stop();
      disarm();
    });
  }
}
