import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

class DeviceStorageService {
  DeviceStorageService._();
  static final DeviceStorageService instance = DeviceStorageService._();

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  dynamic get(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? getMap(String key) {
    final v = get(key);
    return v is Map<String, dynamic> ? v : null;
  }

  Future<void> set(String key, dynamic value) async {
    await load();
    await _prefs!.setString(key, jsonEncode(value));
  }

  Future<void> updateMapEntry({
    required String key,
    required String entryKey,
    required dynamic value,
  }) async {
    await load();
    if (key.isEmpty || entryKey.isEmpty) return;
    final map = getMap(key) ?? <String, dynamic>{};
    map[entryKey] = value;
    await set(key, map);
  }
}
