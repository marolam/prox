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

  Future<String> shortVersion() async {
    if (_cachedShort != null && _cachedShort!.trim().isNotEmpty) {
      return _cachedShort!;
    }
    await _load();
    return _cachedShort ?? "unknown";
  }

  Future<String> fullVersion() async {
    if (_cachedFull != null && _cachedFull!.trim().isNotEmpty) {
      return _cachedFull!;
    }
    await _load();
    return _cachedFull ?? "unknown";
  }

  Future<void> _load() async {
    final full = _defineFullVersion.trim();
    final short = _defineShortVersion.trim();

    _cachedFull = full.isEmpty ? "unknown" : full;
    if (!short.isEmpty) {
      _cachedShort = short;
      return;
    }

    if (full.contains("+")) {
      _cachedShort = full.split("+").first.trim();
    } else {
      _cachedShort = _cachedFull;
    }
  }
}
