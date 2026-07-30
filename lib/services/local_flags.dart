class LocalFlags {
  LocalFlags._();

  static final LocalFlags instance = LocalFlags._();
  static const String kSeenLocationExplainer = "seen_location_explainer";

  final Map<String, bool> _flags = <String, bool>{};

  Future<bool?> getBool(String key) async => _flags[key];

  Future<void> setBool(String key, bool value) async {
    _flags[key] = value;
  }
}