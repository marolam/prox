import "package:geolocator/geolocator.dart";

enum MotionState { unknown, stationary, walking, moving, driving }

class MotionClassifier {
  MotionState currentState = MotionState.unknown;

  void addSample({required double lat, required double lng, required DateTime ts}) {
    currentState = MotionState.stationary;
  }

  MotionState classify({Position? previous, Position? current, double speedMps = 0}) {
    if (speedMps >= 8) return currentState = MotionState.driving;
    if (speedMps >= 1.2) return currentState = MotionState.moving;
    if (speedMps > 0.2) return currentState = MotionState.walking;
    return currentState = MotionState.stationary;
  }
}