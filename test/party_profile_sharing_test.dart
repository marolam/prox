import "package:flutter_test/flutter_test.dart";
import "package:prox/screens/services/party_profile_service.dart";

void main() {
  test("party profile fields are private by default", () {
    const sharing = PartyProfileSharing(
      about: "Private detail",
      contactEmail: "member@example.com",
    );

    expect(sharing.shareAbout, isFalse);
    expect(sharing.shareContactEmail, isFalse);
    expect(sharing.shareHeadline, isFalse);
    expect(sharing.shareKeywords, isFalse);
    expect(sharing.toMap()["shareAbout"], isFalse);
    expect(sharing.toMap()["shareContactEmail"], isFalse);
  });

  test("empty values cannot accidentally be published", () {
    const sharing = PartyProfileSharing(
      shareAbout: true,
      shareContactEmail: true,
      sharePhone: true,
      shareGeneralArea: true,
    );

    expect(sharing.toMap()["shareAbout"], isFalse);
    expect(sharing.toMap()["shareContactEmail"], isFalse);
    expect(sharing.toMap()["sharePhone"], isFalse);
    expect(sharing.toMap()["shareGeneralArea"], isFalse);
  });
}
