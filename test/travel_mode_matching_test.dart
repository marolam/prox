import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/geoquery_service.dart';
import 'package:prox/services/matching/matching_runtime_service.dart';
import 'package:prox/services/matching/travel_match_policy.dart';
import 'package:prox/services/user_profile_service.dart';

void main() {
  final now = DateTime.now();
  Map<String, dynamic> sample({
    int secondsOld = 5,
    double speed = 3,
    bool cached = false,
  }) => {
    'locationTs': Timestamp.fromDate(
      now.subtract(Duration(seconds: secondsOld)),
    ),
    'speedMps': speed,
    'accuracyMeters': 15,
    'cached': cached,
  };
  test('travel requires fresh actual movement, not a recent heartbeat', () {
    expect(TravelMatchPolicy.isMoving(sample(), now), isTrue);
    expect(TravelMatchPolicy.isMoving(sample(secondsOld: 91), now), isFalse);
    expect(TravelMatchPolicy.isMoving(sample(secondsOld: -60), now), isFalse);
    expect(TravelMatchPolicy.isMoving(sample(speed: 0), now), isFalse);
    expect(TravelMatchPolicy.isMoving(sample(cached: true), now), isFalse);
    expect(
      TravelMatchPolicy.isMoving({'ts': Timestamp.fromDate(now)}, now),
      isFalse,
    );
  });
  test('travel accounts for movement since both position samples', () {
    expect(
      TravelMatchPolicy.canMatch(
        local: sample(secondsOld: 60, speed: 25),
        peer: sample(secondsOld: 60, speed: 25),
        distanceMiles: 1,
        radiusMiles: 2,
        now: now,
      ),
      isFalse,
    );
    expect(
      TravelMatchPolicy.canMatch(
        local: sample(),
        peer: sample(),
        distanceMiles: 1,
        radiusMiles: 2,
        now: now,
      ),
      isTrue,
    );
  });
  test(
    'travel matches only moving travel peers with complementary criteria',
    () async {
      NearbyDoc doc(
        String uid,
        String mode,
        Map<String, dynamic> presence, {
        bool compatible = true,
      }) => NearbyDoc(
        uid: uid,
        distanceMiles: .5,
        loc: const GeoPoint(0, 0),
        presenceTs: now,
        data: {
          'modeKind': mode,
          'presence': presence,
          'keywords': {
            'Searching For': <String>[],
            'Can Provide': [compatible ? 'gardening' : 'music'],
          },
        },
      );
      final service = MatchingRuntimeService.forTesting(
        uidProvider: () => 'me',
        travelSampleProvider: sample,
        profileLoader: (uid) async => UserProfile(
          uid: uid,
          searchingFor: const ['gardening'],
          canProvide: const [],
        ),
      );
      final results = await service.filterByModeForSettings(
        [
          doc('moving', 'travel', sample()),
          doc('normal', 'normal', sample()),
          doc('stationary', 'travel', sample(speed: 0)),
          doc('stale', 'travel', sample(secondsOld: 120)),
          doc('unrelated', 'travel', sample(), compatible: false),
        ],
        const MatchDiscoverySettings.defaults().copyWith(
          modeKind: MatchingModeKind.travel,
        ),
      );
      expect(results.map((doc) => doc.uid), ['moving']);
    },
  );
}
