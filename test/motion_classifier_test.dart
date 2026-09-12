import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/motion_classifier.dart';

void main() {
  final start = DateTime.utc(2026, 9, 8);

  test('coordinate samples distinguish walking, moving and driving', () {
    for (final sample in <(double, MotionState)>[
      (0.0004, MotionState.walking), // ~44m over 30s.
      (0.001, MotionState.moving), // ~111m over 30s.
      (0.004, MotionState.driving), // ~445m over 30s.
    ]) {
      final classifier = MotionClassifier();
      classifier.addSample(lat: 0, lng: 0, ts: start);
      expect(classifier.currentState, MotionState.unknown);
      classifier.addSample(
        lat: sample.$1,
        lng: 0,
        ts: start.add(const Duration(seconds: 30)),
      );
      expect(classifier.currentState, sample.$2);
    }
  });

  test(
    'small GPS drift is stationary and invalid samples do not replace anchor',
    () {
      final classifier = MotionClassifier();
      classifier.addSample(lat: 0, lng: 0, ts: start);
      classifier.addSample(
        lat: 0.00003,
        lng: 0,
        ts: start.add(const Duration(seconds: 1)),
      );
      expect(classifier.currentState, MotionState.stationary);
      classifier.addSample(
        lat: double.nan,
        lng: 0,
        ts: start.add(const Duration(seconds: 15)),
      );
      classifier.addSample(
        lat: 95,
        lng: 0,
        ts: start.add(const Duration(seconds: 20)),
      );
      classifier.addSample(lat: 40, lng: 0, ts: start);
      classifier.addSample(
        lat: 0.00043,
        lng: 0,
        ts: start.add(const Duration(seconds: 31)),
      );
      expect(classifier.currentState, MotionState.walking);
    },
  );

  test('long gaps and implausible jumps restart motion confidence', () {
    final classifier = MotionClassifier();
    classifier.addSample(lat: 0, lng: 0, ts: start);
    classifier.addSample(
      lat: 1,
      lng: 0,
      ts: start.add(const Duration(seconds: 1)),
    );
    expect(classifier.currentState, MotionState.unknown);
    classifier.addSample(
      lat: 1.001,
      lng: 0,
      ts: start.add(const Duration(minutes: 6)),
    );
    expect(classifier.currentState, MotionState.unknown);
    classifier.reset();
    classifier.addSample(
      lat: 40,
      lng: -70,
      ts: start.add(const Duration(minutes: 7)),
    );
    expect(classifier.currentState, MotionState.unknown);
  });

  test('speed measurements reject missing or invalid velocity', () {
    final classifier = MotionClassifier();
    for (final speed in [double.nan, double.infinity, -1.0, 100.0]) {
      expect(classifier.classify(speedMps: speed), MotionState.unknown);
    }
    expect(classifier.classify(speedMps: 0), MotionState.stationary);
    expect(classifier.classify(speedMps: 1.4), MotionState.walking);
    expect(classifier.classify(speedMps: 4), MotionState.moving);
    expect(classifier.classify(speedMps: 14), MotionState.driving);
    expect(classifier.classify(), MotionState.unknown);
  });
}
