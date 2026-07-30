import "dart:async";

class UiTelemetryService {
  UiTelemetryService._();
  static final UiTelemetryService instance = UiTelemetryService._();

  final StreamController<Map<String, int>> _countsController =
      StreamController<Map<String, int>>.broadcast();
  final Map<String, int> _counts = <String, int>{};

  Stream<Map<String, int>> get countsStream => _countsController.stream;

  Map<String, int> peekCounts() => Map<String, int>.unmodifiable(_counts);

  void log(
    String event, {
    Map<String, Object?> data = const <String, Object?>{},
    Map<String, Object?>? meta,
  }) {
    _counts[event] = (_counts[event] ?? 0) + 1;
    if (!_countsController.isClosed) {
      _countsController.add(peekCounts());
    }
  }
}
