class LocationPermissions {
  LocationPermissions._();

  static final LocationPermissions instance = LocationPermissions._();

  Future<bool> isGranted() async => true;

  Future<bool> requestFromUserAction() async => true;
}