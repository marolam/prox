import "package:package_info_plus/package_info_plus.dart";

class AppBuildInfoService {
  AppBuildInfoService._();
  static final AppBuildInfoService instance = AppBuildInfoService._();

  static const String _defineFullVersion = String.fromEnvironment(
    "PROX_APP_VERSION",
    defaultValue: "unknown",
  );
  static const String _defineShortVersion = String.fromEnvironment(
    "PROX_APP_VERSION_SHORT",
    defaultValue: "unknown",
  );

  String? _cachedShort;
  String? _cachedFull;
  Future<void>? _loading;

  Future<String> shortVersion() async {
    if (_cachedShort != null &&
        _cachedShort != 'unknown' &&
        _cachedShort!.trim().isNotEmpty) {
      return _cachedShort!;
    }
    await _ensureLoaded();
    return _cachedShort ?? "unknown";
  }

  Future<String> fullVersion() async {
    if (_cachedFull != null &&
        _cachedFull != 'unknown' &&
        _cachedFull!.trim().isNotEmpty) {
      return _cachedFull!;
    }
    await _ensureLoaded();
    return _cachedFull ?? "unknown";
  }

  Future<void> _ensureLoaded() async {
    try {
      await (_loading ??= _load());
    } finally {
      _loading = null;
    }
  }

  Future<void> _load() async {
    final full = _defineFullVersion.trim();
    final short = _defineShortVersion.trim();

    // The installed package is authoritative; stale build defines must not
    // bypass a gate or report a different version on Android and iOS.
    try {
      final package =
          await PackageInfo.fromPlatform().timeout(const Duration(seconds: 3));
      final packageVersion = package.version.trim();
      final buildNumber = package.buildNumber.trim();
      _cachedShort = packageVersion.isEmpty ? "unknown" : packageVersion;
      _cachedFull = packageVersion.isEmpty
          ? "unknown"
          : (buildNumber.isEmpty
              ? packageVersion
              : "$packageVersion+$buildNumber");
      if (packageVersion.isNotEmpty) return;
    } catch (_) {
      _cachedFull = "unknown";
    }

    if (full.isNotEmpty && full != "unknown") {
      _cachedFull = full;
      _cachedShort = short.isNotEmpty && short != "unknown"
          ? short
          : full.split("+").first.trim();
      return;
    }

    if (short.isNotEmpty && short != "unknown") {
      _cachedShort = short;
      _cachedFull = short;
      return;
    }
    _cachedShort = "unknown";
  }
}
