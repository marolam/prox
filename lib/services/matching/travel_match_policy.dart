import 'package:cloud_firestore/cloud_firestore.dart';

/// A heartbeat is not a new location fix. Travel uses the fix timestamp and
/// accounts for how far both people could have moved since their samples.
class TravelMatchPolicy {
  static const maxSampleAge = Duration(seconds: 90);

  static bool isMoving(Map<String, dynamic> sample, DateTime now) {
    final timestamp = sample['locationTs'];
    final speed = sample['speedMps'];
    final accuracy = sample['accuracyMeters'];
    if (timestamp is! Timestamp || speed is! num || accuracy is! num) {
      return false;
    }
    final age = now.difference(timestamp.toDate());
    return sample['cached'] != true &&
        age >= const Duration(seconds: -5) &&
        age <= maxSampleAge &&
        speed.isFinite &&
        speed >= 0.6 &&
        speed <= 100 &&
        accuracy.isFinite &&
        accuracy >= 0 &&
        accuracy <= 100;
  }

  static double uncertaintyMiles(Map<String, dynamic> sample, DateTime now) {
    final age = now.difference((sample['locationTs'] as Timestamp).toDate());
    final seconds = age.inMilliseconds.clamp(0, 90000) / 1000;
    return ((sample['accuracyMeters'] as num) +
            (sample['speedMps'] as num) * seconds) /
        1609.344;
  }

  static bool canMatch({
    required Map<String, dynamic> local,
    required Map<String, dynamic> peer,
    required double distanceMiles,
    required double radiusMiles,
    required DateTime now,
  }) =>
      isMoving(local, now) &&
      isMoving(peer, now) &&
      distanceMiles +
              uncertaintyMiles(local, now) +
              uncertaintyMiles(peer, now) <=
          radiusMiles;
}
