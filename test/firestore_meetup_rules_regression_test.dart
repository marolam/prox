import "dart:io";

import "package:flutter_test/flutter_test.dart";

void main() {
  test("meetup rules allow transaction preflight for a missing pair document",
      () {
    final rules = File("firestore.rules").readAsStringSync();

    expect(
      rules,
      contains("resource == null || meetupParticipant(resource.data)"),
    );
    expect(
      rules,
      contains(
        "allow create: if authed() && meetupParticipant(request.resource.data)",
      ),
    );
  });

  test("legacy meetups without status events allow location-only updates", () {
    final rules = File("firestore.rules").readAsStringSync();

    expect(
      rules,
      contains('!request.resource.data.keys().hasAny(["lastStatusEvent"])'),
    );
    expect(
      rules,
      contains('!resource.data.keys().hasAny(["lastStatusEvent"])'),
    );
  });
}
