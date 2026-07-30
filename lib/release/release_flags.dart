import "package:flutter/foundation.dart";

/// ReleaseFlags
/// Centralized toggles for tester builds vs production builds.
/// Keep this file boring and predictable - it gets referenced everywhere.
class ReleaseFlags {
  ReleaseFlags._();

  /// Tester build marker. Keep true during tester phases; set
  /// `--dart-define=PROX_TESTER_BUILD=false` for store-hardening builds.
  static const bool testerBuild =
      bool.fromEnvironment("PROX_TESTER_BUILD", defaultValue: true);

  /// True in Flutter release mode.
  static bool get isRelease => kReleaseMode;

  /// Dev-only panels, debug cards, and "E2E Debug" blocks.
  /// Keep disabled in release builds by default.
  static bool get devToolsEnabled => !kReleaseMode;

  /// Show small build markers (version/build-time) on UI surfaces.
  static bool get showBuildInfo => !kReleaseMode;

  /// If true, allow extra verbose logs.
  static bool get verboseLogs => !kReleaseMode;

  /// If true, allow permissive UX fallbacks (e.g., "Proceed without X").
  /// For tester builds we keep some of these available; for store builds
  /// you can tighten later.
  static bool get permissiveTesterUX => testerBuild || !kReleaseMode;

  /// Pro Mode preview is account-gated while recovered features are tested.
  static const bool proModePreviewEnabled = bool.fromEnvironment(
    "PROX_PRO_MODE_PREVIEW_ENABLED",
    defaultValue: true,
  );

  /// Build-level Pro Mode availability. Account access is still preview-gated.
  static const bool businessModeEnabled = bool.fromEnvironment(
    "PROX_BUSINESS_MODE_ENABLED",
    defaultValue: true,
  );

  /// Emergency build-time off switch for Pro Mode surfaces.
  static const bool businessModeForceOff = bool.fromEnvironment(
    "PROX_BUSINESS_MODE_FORCE_OFF",
    defaultValue: false,
  );

  /// Comma/semicolon/space separated login allowlist for Pro Mode preview.
  static const String proModePreviewLogins = String.fromEnvironment(
    "PROX_PRO_MODE_PREVIEW_LOGINS",
    defaultValue: "marty.marola@hotmail.com",
  );
}
