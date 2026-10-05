import "package:flutter_test/flutter_test.dart";

import "package:prox/services/meetup_service.dart";

void main() {
  group("MeetupService.requiredSessionScreenFromData", () {
    test("routes live only when confirmed location has valid numeric values", () {
      final result = MeetupService.requiredSessionScreenForData(
        <String, dynamic>{
          "status": "live",
          "locationStatus": "confirmed",
          "lat": 40.7128,
          "lng": -74.0060,
        },
      );

      expect(result, "live");
    });

    test("accepts numeric coordinate strings for confirmed live meetups", () {
      final result = MeetupService.requiredSessionScreenForData(
        <String, dynamic>{
          "status": "live",
          "locationStatus": "confirmed",
          "lat": "40.7128",
          "lng": "-74.0060",
        },
      );

      expect(result, "live");
    });

    test("keeps planner when confirmed location coordinates are invalid", () {
      final result = MeetupService.requiredSessionScreenForData(
        <String, dynamic>{
          "status": "live",
          "locationStatus": "confirmed",
          "lat": "north",
          "lng": "west",
        },
      );

      expect(result, "planner");
    });

    test("keeps planner when confirmed location is out of bounds", () {
      final result = MeetupService.requiredSessionScreenForData(
        <String, dynamic>{
          "status": "live",
          "locationStatus": "confirmed",
          "lat": "95",
          "lng": "-181",
        },
      );

      expect(result, "planner");
    });
  });
}
