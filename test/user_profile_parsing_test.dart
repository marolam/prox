import "package:flutter_test/flutter_test.dart";
import "package:prox/services/user_profile_service.dart";

void main() {
  test("fromMap normalizes and deduplicates keyword lists", () {
    final profile = UserProfile.fromMap("u1", {
      "keywords": {
        "Searching For": [
          "  Gardening  ",
          "gardening",
          "GARDENING",
          "home   repair",
          "",
          "  home repair  ",
        ],
        "Can Provide": [
          " tutoring ",
          "Tutoring",
          "bike   repair",
          "bike repair",
        ],
      },
    });

    expect(profile.searchingFor, ["Gardening", "home repair"]);
    expect(profile.canProvide, ["tutoring", "bike repair"]);
  });

  test("fromMap supports legacy top-level keyword keys with normalization", () {
    final profile = UserProfile.fromMap("u2", {
      "Searching For": ["  coding", "coding  ", "code   review"],
      "Can Provide": [" mentoring", "MENTORING", "pair   programming"],
    });

    expect(profile.searchingFor, ["coding", "code review"]);
    expect(profile.canProvide, ["mentoring", "pair programming"]);
  });

  test("fromMap ignores placeholder photo values and uses next valid url", () {
    final profile = UserProfile.fromMap("u3", {
      "photoUrl": "null",
      "selfieUrl": "   ",
      "avatarUrl": "https://cdn.example.com/u3.jpg",
    });

    expect(profile.photoUrl, "https://cdn.example.com/u3.jpg");
  });

  test("fromMap treats placeholder-only photo values as missing", () {
    final profile = UserProfile.fromMap("u4", {
      "photoUrl": "undefined",
      "avatar": "(null)",
      "photo": "https://",
    });

    expect(profile.photoUrl, isNull);
  });
}
