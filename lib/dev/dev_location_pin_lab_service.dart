import "package:cloud_firestore/cloud_firestore.dart";

import "package:prox/services/device_storage_service.dart";

enum DevLocationPinKind {
  selfDemoLocation,
  simulatedNearbyUser,
  meetupLocation,
  treasureTarget,
  generic,
}

class DevLocationPin {
  const DevLocationPin({
    required this.kind,
    required this.lat,
    required this.lng,
    required this.updatedAtMs,
  });

  final DevLocationPinKind kind;
  final double lat;
  final double lng;
  final int updatedAtMs;

  GeoPoint toGeoPoint() => GeoPoint(lat, lng);

  Map<String, Object> toJson() {
    return <String, Object>{
      "kind": kind.name,
      "lat": lat,
      "lng": lng,
      "updatedAtMs": updatedAtMs,
    };
  }

  static DevLocationPin? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final kindName = (map["kind"] ?? "").toString();
    final kind = DevLocationPinKind.values.where((v) => v.name == kindName).cast<DevLocationPinKind?>().firstWhere(
      (v) => v != null,
      orElse: () => null,
    );
    final lat = map["lat"];
    final lng = map["lng"];
    final updatedAtMs = map["updatedAtMs"];
    if (kind == null || lat is! num || lng is! num) return null;
    return DevLocationPin(
      kind: kind,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      updatedAtMs: updatedAtMs is num ? updatedAtMs.toInt() : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class DevLocationPinLabService {
  DevLocationPinLabService._();
  static final DevLocationPinLabService instance = DevLocationPinLabService._();

  static const String _storageKey = "dev_location_pin_lab.v1";

  final Map<DevLocationPinKind, DevLocationPin> _pins = <DevLocationPinKind, DevLocationPin>{};
  bool _loaded = false;

  Map<DevLocationPinKind, DevLocationPin> get pins => Map<DevLocationPinKind, DevLocationPin>.unmodifiable(_pins);

  DevLocationPin? pinFor(DevLocationPinKind kind) => _pins[kind];

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await DeviceStorageService.instance.load();
    final raw = DeviceStorageService.instance.getMap(_storageKey);
    if (raw == null) return;

    for (final entry in raw.entries) {
      final kind = DevLocationPinKind.values.where((v) => v.name == entry.key).cast<DevLocationPinKind?>().firstWhere(
        (v) => v != null,
        orElse: () => null,
      );
      if (kind == null) continue;
      final decoded = DevLocationPin.fromJson(entry.value);
      if (decoded != null) {
        _pins[kind] = decoded;
      }
    }
  }

  Future<void> setPin({
    required DevLocationPinKind kind,
    required double lat,
    required double lng,
  }) async {
    await ensureLoaded();
    _pins[kind] = DevLocationPin(
      kind: kind,
      lat: lat,
      lng: lng,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
  }

  Future<void> clearPin(DevLocationPinKind kind) async {
    await ensureLoaded();
    _pins.remove(kind);
    await _persist();
  }

  Future<void> clearAll() async {
    await ensureLoaded();
    _pins.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final out = <String, Object>{};
    for (final entry in _pins.entries) {
      out[entry.key.name] = entry.value.toJson();
    }
    await DeviceStorageService.instance.set(_storageKey, out);
  }
}
