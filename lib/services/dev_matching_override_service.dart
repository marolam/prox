class DevMatchingOverrideService {
  DevMatchingOverrideService._();

  static final DevMatchingOverrideService instance = DevMatchingOverrideService._();

  bool unlimitedRadius = false;

  Future<void> setUnlimitedRadius(bool value) async {
    unlimitedRadius = value;
  }
}