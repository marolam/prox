import "package:flutter/foundation.dart";
import "package:geolocator/geolocator.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:prox/services/app_lifecycle_service.dart";
import "package:prox/services/runtime_diagnostics_service.dart";

class LocationPrivacySnapshot {
  const LocationPrivacySnapshot({
    required this.serviceEnabled,
    required this.permission,
  });
  final bool serviceEnabled;
  final LocationPermission permission;
  bool get isGranted =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

class LocationPrivacyService extends ChangeNotifier {
  LocationPrivacyService._({
    Future<SharedPreferences> Function()? preferences,
    Future<void> Function()? expirePresence,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _expireOverride = expirePresence;

  @visibleForTesting
  factory LocationPrivacyService.forTesting({
    required Future<SharedPreferences> Function() preferences,
    required Future<void> Function() expirePresence,
  }) => LocationPrivacyService._(
    preferences: preferences,
    expirePresence: expirePresence,
  );

  static final LocationPrivacyService instance = LocationPrivacyService._();
  static const preferenceKey = "prox_location_enabled";
  final Future<SharedPreferences> Function() _preferences;
  final Future<void> Function()? _expireOverride;
  Future<void>? _loading;
  Future<void> _persisting = Future<void>.value();
  bool _loaded = false;
  bool _locationEnabled = true;
  int _revision = 0;
  bool get locationEnabled => _locationEnabled;
  bool get mayReadLocation =>
      _loaded && _locationEnabled && AppLifecycleService.instance.isForeground;

  LocationPrivacySnapshot _lastSnapshot = const LocationPrivacySnapshot(
    serviceEnabled: false,
    permission: LocationPermission.denied,
  );

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final preferences = await _preferences();
      if (_revision == revision) {
        _locationEnabled = preferences.getBool(preferenceKey) ?? true;
        _loaded = true;
        notifyListeners();
      }
    } finally {
      _loading = null;
    }
  }

  Future<LocationPrivacySnapshot> snapshot() async {
    await ensureLoaded();
    bool serviceEnabled = false;
    LocationPermission permission = LocationPermission.denied;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(seconds: 5),
      );
      permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}
    _lastSnapshot = LocationPrivacySnapshot(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
    return _lastSnapshot;
  }

  Future<void> setLocationEnabled(bool enabled) async {
    // Notify synchronously so running GPS callbacks cannot publish another fix.
    _revision++;
    _loaded = true;
    _locationEnabled = enabled;
    notifyListeners();
    Future<void> Function()? expire;
    if (!enabled) {
      expire = _expireOverride;
      if (expire == null) {
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            final ref = FirebaseFirestore.instance.doc(
              "users/$uid/presence/current",
            );
            expire = () => ref.delete().timeout(const Duration(seconds: 5));
          }
        } catch (_) {}
      }
    }
    final expirePending = expire == null
        ? Future<void>.value()
        : expire().catchError((Object error, StackTrace stack) {
            RuntimeDiagnosticsService.instance.record(
              error,
              stack,
              operation: "Remove shared presence",
            );
          });
    _persisting = _persisting.catchError((Object _) {}).then((_) async {
      final preferences = await _preferences();
      await preferences.setBool(preferenceKey, enabled);
    });
    try {
      await _persisting;
    } finally {
      await expirePending;
    }
  }

  LocationPrivacySnapshot get lastSnapshot => _lastSnapshot;
}
