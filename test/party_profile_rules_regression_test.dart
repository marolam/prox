import "dart:io";

import "package:flutter_test/flutter_test.dart";

void main() {
  test("Party profile reads require mutual canonical Party membership", () {
    final rules = File("firestore.rules").readAsStringSync();

    expect(rules, contains("function isMutualPartyMember(uid)"));
    expect(
      rules,
      contains("users/\$(uid)/party/\$(request.auth.uid)"),
    );
    expect(
      rules,
      contains("users/\$(request.auth.uid)/party/\$(uid)"),
    );
    expect(rules, contains("match /partyProfile/{docId}"));
    expect(
      rules,
      contains("allow read: if isOwner(uid) || isMutualPartyMember(uid);"),
    );
  });
}
