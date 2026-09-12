import "package:flutter_test/flutter_test.dart";
import "package:prox/services/meetup_coordination_service.dart";

void main() {
  test("coordination info reports useful free directional guidance", () {
    final info = MeetupCoordinationInfo.between(
      fromLat: 26.0,
      fromLng: -80.0,
      toLat: 26.001,
      toLng: -80.0,
    );

    expect(info.distanceMeters, inInclusiveRange(100, 120));
    expect(info.cardinalDirection, "N");
    expect(info.roughWalkingMinutes, greaterThanOrEqualTo(1));
  });

  test("distance label switches to kilometers", () {
    const info = MeetupCoordinationInfo(
      distanceMeters: 1540,
      bearingDegrees: 90,
      cardinalDirection: "E",
      roughWalkingMinutes: 19,
    );

    expect(info.distanceLabel, "1.5 km");
  });
}
