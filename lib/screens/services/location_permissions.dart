import "package:geolocator/geolocator.dart";

/// LocationPermissions
/// Pure permission/status helper. Keeps "OS prompt" calls strictly behind user actions.
class LocationPermissions {
  LocationPermissions._();
  static final LocationPermissions instance = LocationPermissions._();

  Future<bool> isGranted() async {
    try {
      // Check permission first — do NOT hard-gate on isLocationServiceEnabled().
      // Samsung AppOps race causes that call to return false during startup even
      // when location is functional.  If runtime permission is granted, trust it.
      final LocationPermission p = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 6), onTimeout: () => LocationPermission.denied);
      if (p == LocationPermission.always || p == LocationPermission.whileInUse) return true;

      // Permission not granted — no point checking service.
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Call this ONLY as a direct result of a user tap.
  Future<bool> requestFromUserAction() async {
    try {
      LocationPermission p = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 6), onTimeout: () => LocationPermission.denied);
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 10), onTimeout: () => LocationPermission.denied);
      }

      // If permission is granted, treat this as success even if service probe is
      // momentarily flaky during startup. Runtime reads will surface true OFF state.
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }

  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
  }
}
