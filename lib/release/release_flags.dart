import "package:flutter/foundation.dart";

/// ReleaseFlags
/// Centralized toggles for tester builds vs production builds.
/// Keep this file boring and predictable - it gets referenced everywhere.
class ReleaseFlags {
  ReleaseFlags._();

  /// Tester build marker. Keep true during tester phases; set
  /// `--dart-define=PROX_TESTER_BUILD=false` for store-hardening builds.
  static const bool testerBuild = bool.fromEnvironment("PROX_TESTER_BUILD", defaultValue: true);

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
}
