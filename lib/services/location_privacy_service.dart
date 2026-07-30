import "package:flutter/foundation.dart";
import "package:geolocator/geolocator.dart";

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
  LocationPrivacyService._();

  static final LocationPrivacyService instance = LocationPrivacyService._();

  bool locationEnabled = true;
  LocationPrivacySnapshot _lastSnapshot = const LocationPrivacySnapshot(
    serviceEnabled: true,
    permission: LocationPermission.denied,
  );

  Future<void> ensureLoaded() async {
    await snapshot();
  }

  Future<LocationPrivacySnapshot> snapshot() async {
    bool serviceEnabled = true;
    LocationPermission permission = LocationPermission.denied;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      permission = await Geolocator.checkPermission();
    } catch (_) {}
    _lastSnapshot = LocationPrivacySnapshot(
      serviceEnabled: serviceEnabled,
      permission: permission,
    );
    return _lastSnapshot;
  }

  Future<void> setLocationEnabled(bool enabled) async {
    locationEnabled = enabled;
    notifyListeners();
  }

  LocationPrivacySnapshot get lastSnapshot => _lastSnapshot;
}