import "package:flutter_test/flutter_test.dart";
import "package:prox/services/pro_mode_preview_access.dart";

void main() {
  group("ProModePreviewAccess", () {
    test("defaults to Marty-only preview login", () {
      expect(
        ProModePreviewAccess.isAllowed(
          uid: "any-uid",
          email: "marty.marola@hotmail.com",
          allowlist: "marty.marola@hotmail.com",
          previewEnabled: true,
        ),
        isTrue,
      );

      expect(
        ProModePreviewAccess.isAllowed(
          uid: "any-uid",
          email: "tester@example.com",
          allowlist: "marty.marola@hotmail.com",
          previewEnabled: true,
        ),
        isFalse,
      );
    });

    test("allows matching uid or email when preview is enabled", () {
      expect(
        ProModePreviewAccess.isAllowed(
          uid: "abc123",
          email: "marty@example.com",
          allowlist: "other, abc123",
          previewEnabled: true,
        ),
        isTrue,
      );

      expect(
        ProModePreviewAccess.isAllowed(
          uid: "abc123",
          email: "Marty@Example.com",
          allowlist: "friend@example.com; marty@example.com",
          previewEnabled: true,
        ),
        isTrue,
      );
    });

    test("blocks when preview is disabled or login is not listed", () {
      expect(
        ProModePreviewAccess.isAllowed(
          uid: "abc123",
          email: "marty@example.com",
          allowlist: "abc123",
          previewEnabled: false,
        ),
        isFalse,
      );

      expect(
        ProModePreviewAccess.isAllowed(
          uid: "abc123",
          email: "marty@example.com",
          allowlist: "someone-else",
          previewEnabled: true,
        ),
        isFalse,
      );
    });
  });
}
