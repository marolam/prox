import "dart:io";

import "package:flutter_test/flutter_test.dart";

void main() {
  test("Party network results are owner-only in Firestore rules", () {
    final rules = File("firestore.rules").readAsStringSync();
    expect(rules, contains("match /partyNetworkRequests/{uid}"));
    expect(rules, contains("allow read: if isOwner(uid)"));
    expect(
        rules, contains("request.resource.data.ownerUid == request.auth.uid"));
  });

  test("Party network backend returns aggregates without identity lists", () {
    final source = File("functions_notifications/index.js").readAsStringSync();
    expect(source, contains("secondDegreeProfiles: consentingProfiles"));
    expect(source, contains("topWants: topCounts(wants)"));
    expect(source, isNot(contains("secondDegreeUids:")));
    expect(source, isNot(contains("candidateUids:")));
  });
}
