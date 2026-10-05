import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/services/meetup_service.dart";

void main() {
  test("declined without declinedAt still enforces defensive cooldown", () {
    const state = MeetupRequestState(status: "declined", requestedBy: "other");

    final left = MeetupService.declineCooldownLeftFromState(state);

    expect(left, MeetupService.declineCooldown);
  });

  test("declined with declinedAt uses remaining cooldown", () {
    final declinedAt = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(minutes: 2)),
    );
    final state = MeetupRequestState(
      status: "declined",
      requestedBy: "other",
      declinedAt: declinedAt,
    );

    final left = MeetupService.declineCooldownLeftFromState(state);

    expect(left, isNotNull);
    expect(left, greaterThan(const Duration(minutes: 7)));
    expect(left, lessThanOrEqualTo(MeetupService.declineCooldown));
  });
}
