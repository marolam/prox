import "package:flutter/foundation.dart";

class BuildInfo {
  final String version;
  final String build;
  final DateTime builtAt;

  const BuildInfo({
    required this.version,
    required this.build,
    required this.builtAt,
  });

  String get shortLabel => "v$version ($build)";
}

class BuildInfoService {
  BuildInfoService._();
  static final BuildInfoService instance = BuildInfoService._();

  final BuildInfo info = BuildInfo(
    version: const String.fromEnvironment(
      "PROX_VERSION",
      defaultValue: "0.18.0",
    ),
    build: const String.fromEnvironment(
      "PROX_BUILD",
      defaultValue: "dev",
    ),
    builtAt: DateTime.fromMillisecondsSinceEpoch(
      const int.fromEnvironment(
        "PROX_BUILT_AT",
        defaultValue: 0,
      ),
      isUtc: true,
    ),
  );

  void debugLog() {
    if (kDebugMode) {
      debugPrint(
        "[Build] version=${info.version} build=${info.build} builtAt=${info.builtAt.toIso8601String()}",
      );
    }
  }
}
