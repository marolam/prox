import "package:flutter_test/flutter_test.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/services/matching/matching_runtime_service.dart";

void main() {
  group("Normal mode intent matching", () {
    test("active can match active or passive, while passive requires active",
        () {
      expect(
        MatchingRuntimeService.normalModesCanMatch(
          local: NormalMatchMode.active,
          peer: NormalMatchMode.active,
        ),
        isTrue,
      );
      expect(
        MatchingRuntimeService.normalModesCanMatch(
          local: NormalMatchMode.active,
          peer: NormalMatchMode.passive,
        ),
        isTrue,
      );
      expect(
        MatchingRuntimeService.normalModesCanMatch(
          local: NormalMatchMode.passive,
          peer: NormalMatchMode.active,
        ),
        isTrue,
      );
      expect(
        MatchingRuntimeService.normalModesCanMatch(
          local: NormalMatchMode.passive,
          peer: NormalMatchMode.passive,
        ),
        isFalse,
      );
      expect(
        MatchingRuntimeService.normalModesCanMatch(
          local: NormalMatchMode.active,
          peer: null,
        ),
        isFalse,
      );
    });

    test("accepts either complementary intent direction", () {
      expect(
        MatchingRuntimeService.hasComplementaryIntent(
          mySearching: const <String>["plumbing"],
          myProviding: const <String>["web design"],
          theirSearching: const <String>["web design"],
          theirProviding: const <String>["gardening"],
        ),
        isTrue,
      );
    });

    test("rejects shared wants that no one can provide", () {
      expect(
        MatchingRuntimeService.hasComplementaryIntent(
          mySearching: const <String>["plumbing"],
          myProviding: const <String>["web design"],
          theirSearching: const <String>["plumbing"],
          theirProviding: const <String>["gardening"],
        ),
        isFalse,
      );
    });

    test("fails closed when either profile lacks complete intent", () {
      expect(
        MatchingRuntimeService.hasComplementaryIntent(
          mySearching: const <String>["plumbing"],
          myProviding: const <String>[],
          theirSearching: const <String>["web design"],
          theirProviding: const <String>["plumbing"],
        ),
        isFalse,
      );
    });
  });
}
