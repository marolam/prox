import "package:geolocator/geolocator.dart";

enum MotionState { unknown, stationary, walking, moving, driving }

class MotionClassifier {
  MotionState currentState = MotionState.unknown;
  ({double lat, double lng, DateTime ts})? _previous;
  static const _maximumGap = Duration(minutes: 5);
  static const _jitterMeters = 8.0;
  static const _maximumPlausibleSpeed = 80.0;

  void reset() {
    _previous = null;
    currentState = MotionState.unknown;
  }

  void addSample({
    required double lat,
    required double lng,
    required DateTime ts,
  }) {
    if (!_validCoordinates(lat, lng)) return;
    final previous = _previous;
    if (previous != null && !ts.isAfter(previous.ts)) return;
    _previous = (lat: lat, lng: lng, ts: ts);
    if (previous == null || ts.difference(previous.ts) > _maximumGap) {
      currentState = MotionState.unknown;
      return;
    }
    currentState = _fromPositions(
      previous.lat,
      previous.lng,
      previous.ts,
      lat,
      lng,
      ts,
    );
  }

  MotionState classify({
    Position? previous,
    Position? current,
    double? speedMps,
  }) {
    if (speedMps != null) return currentState = _fromSpeed(speedMps);
    if (previous == null || current == null)
      return currentState = MotionState.unknown;
    return currentState = _fromPositions(
      previous.latitude,
      previous.longitude,
      previous.timestamp,
      current.latitude,
      current.longitude,
      current.timestamp,
    );
  }

  static bool _validCoordinates(double lat, double lng) =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  static MotionState _fromPositions(
    double lat1,
    double lng1,
    DateTime ts1,
    double lat2,
    double lng2,
    DateTime ts2,
  ) {
    final elapsed = ts2.difference(ts1);
    if (!_validCoordinates(lat1, lng1) ||
        !_validCoordinates(lat2, lng2) ||
        elapsed <= Duration.zero ||
        elapsed > _maximumGap)
      return MotionState.unknown;
    final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    // Low-accuracy stationary fixes drift; do not wake GPS more frequently for
    // movements smaller than the noise floor.
    if (meters <= _jitterMeters) return MotionState.stationary;
    return _fromSpeed(meters / (elapsed.inMicroseconds / 1000000));
  }

  static MotionState _fromSpeed(double speed) {
    if (!speed.isFinite || speed < 0 || speed > _maximumPlausibleSpeed)
      return MotionState.unknown;
    if (speed >= 8) return MotionState.driving;
    if (speed >= 2.5) return MotionState.moving;
    if (speed > 0.3) return MotionState.walking;
    return MotionState.stationary;
  }
}
