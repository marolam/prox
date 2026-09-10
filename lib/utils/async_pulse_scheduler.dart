import 'dart:async';

/// Runs one asynchronous burst at a time, waiting a full interval after each.
/// Stopping invalidates pending callbacks, including work from a prior session.
class AsyncPulseScheduler {
  AsyncPulseScheduler({
    required this.interval,
    required this.canRun,
    required this.action,
    required this.onError,
  });

  final Duration Function() interval;
  final bool Function() canRun;
  final Future<void> Function() action;
  final void Function(Object, StackTrace) onError;
  Timer? _timer;
  bool _active = false;
  bool _inFlight = false;
  int _generation = 0;

  void start({bool immediate = false}) {
    if (_active || !canRun()) return;
    _active = true;
    _generation++;
    _schedule(_generation, immediate: immediate);
  }

  void stop() {
    _active = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(int generation, {bool immediate = false}) {
    if (!_active || generation != _generation) return;
    final delay = interval();
    _timer = Timer(
      immediate
          ? Duration.zero
          : (delay > Duration.zero ? delay : const Duration(milliseconds: 1)),
      () => unawaited(_tick(generation)),
    );
  }

  Future<void> _tick(int generation) async {
    if (!_active || generation != _generation) return;
    _timer = null;
    if (!canRun()) {
      stop();
      return;
    }
    if (_inFlight) {
      _schedule(generation);
      return;
    }
    _inFlight = true;
    try {
      await action();
    } catch (error, stack) {
      onError(error, stack);
    } finally {
      _inFlight = false;
      _schedule(generation);
    }
  }
}
