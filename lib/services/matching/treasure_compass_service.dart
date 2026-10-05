import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/matching/treasure_area_snapshot.dart';
import 'package:prox/services/device_location_resolver.dart';
import 'package:prox/services/geoquery_service.dart';
import 'package:prox/services/location_privacy_service.dart';
import 'package:prox/services/matching/matching_runtime_service.dart';
import 'package:prox/services/party_service.dart';
import 'package:prox/services/privacy/block_service.dart';

export 'package:prox/services/matching/treasure_area_snapshot.dart';

class TreasureCompassService {
  TreasureCompassService._();
  static final instance = TreasureCompassService._();

  String? _uid;
  MatchDiscoverySettings? _settings;
  TreasureAreaSnapshot? _cached;
  Future<TreasureAreaSnapshot>? _pending;
  int _revision = 0;

  void clearSession() {
    _revision++;
    _uid = null;
    _settings = null;
    _cached = null;
    _pending = null;
  }

  Future<TreasureAreaSnapshot> snapshot(MatchDiscoverySettings settings) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !LocationPrivacyService.instance.mayReadLocation) {
      clearSession();
      throw StateError('Location and sign-in are required for the compass.');
    }
    if (_uid != uid || _settings != settings) {
      clearSession();
      _uid = uid;
      _settings = settings;
    }
    final cached = _cached;
    if (cached != null && !cached.isExpired(DateTime.now())) return cached;
    return _pending ??= _load(uid, settings, _revision);
  }

  Future<TreasureAreaSnapshot> _load(
    String uid,
    MatchDiscoverySettings settings,
    int revision,
  ) async {
    bool current() =>
        revision == _revision &&
        FirebaseAuth.instance.currentUser?.uid == uid &&
        LocationPrivacyService.instance.mayReadLocation;
    try {
      final fix = await DeviceLocationResolver.instance.resolve(
        maxCachedAge: const Duration(minutes: 2),
        isCurrent: current,
      );
      final position = fix.position;
      if (position == null || !current()) {
        throw StateError('Waiting for a recent location.');
      }
      final origin = GeoPoint(position.latitude, position.longitude);
      var raw = await GeoQueryService.instance
          .streamNearby(
            center: origin,
            radiusMiles: settings.treasureRadiusMiles,
            limitUsers: 50,
            snapshotOnly: true,
          )
          .first
          .timeout(const Duration(seconds: 15));
      if (!current()) throw StateError('Compass session changed.');
      if (GeoQueryService.instance.debug.status != GeoQueryStatus.ready) {
        throw StateError('The area snapshot could not be loaded.');
      }
      Set<String>? members;
      if (settings.partyScope == MatchPartyScope.partyOnly ||
          settings.partyScope == MatchPartyScope.tree ||
          settings.partyScope == MatchPartyScope.extendedOnly) {
        final entries = await PartyService.instance
            .watchMyPartyEntries()
            .first
            .timeout(const Duration(seconds: 5));
        members = entries.map((entry) => entry.otherUid).toSet();
      }
      await BlockService.instance.ready.timeout(const Duration(seconds: 5));
      if (!current()) throw StateError('Compass session changed.');
      raw = raw
          .where((doc) {
            final age = (doc.data['ageYears'] ?? doc.data['age']) as num?;
            return !BlockService.instance.isBlockedSync(doc.uid) &&
                doc.data['busyInMeetup'] != true &&
                (!settings.businessOnly ||
                    !settings.immediateOnly ||
                    (doc.availabilityMinutes != null &&
                        doc.availabilityMinutes! <= 0)) &&
                (!settings.businessOnly || doc.isBusiness) &&
                (members == null || members.contains(doc.uid)) &&
                (settings.ageBracket == MatchAgeBracket.any ||
                    (age != null &&
                        age >= settings.ageBracket.minAge! &&
                        (settings.ageBracket.maxAge == null ||
                            age <= settings.ageBracket.maxAge!)));
          })
          .toList(growable: false);
      final targets = await MatchingRuntimeService.instance.rankTreasureTargets(
        raw,
        settings: settings,
      );
      if (!current()) throw StateError('Compass session changed.');
      return _cached = TreasureAreaSnapshot.fromTargets(
        origin: origin,
        targets: targets,
        now: DateTime.now(),
      );
    } finally {
      if (revision == _revision) _pending = null;
    }
  }
}
