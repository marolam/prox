import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "dart:math" as math;

import "package:prox/services/ttl_policy.dart";
import "package:prox/services/location_privacy_service.dart";
import "package:prox/services/device_location_resolver.dart";
import "package:prox/services/runtime_diagnostics_service.dart";
import "package:prox/utils/bounded_async_map.dart";
import "package:prox/utils/geo_query_bounds.dart";

class NearbyDoc {
  const NearbyDoc({
    required this.uid,
    required this.distanceMiles,
    required this.loc,
    required this.data,
    this.presenceTs,
  });

  final String uid;
  final double distanceMiles;
  final GeoPoint loc;
  final Map<String, dynamic> data;
  final DateTime? presenceTs;

  bool get isBusiness =>
      data["isBusiness"] == true || data["businessMode"] == true;

  int? get availabilityMinutes =>
      (data["availabilityMinutes"] as num?)?.toInt();
}

enum GeoQueryStatus {
  idle,
  loading,
  ready,
  locationOff,
  locationUnavailable,
  queryError,
}

class GeoQueryDebug extends ChangeNotifier {
  GeoQueryStatus status = GeoQueryStatus.idle;
  String lastError = "";
  bool centerKnown = false;
  String centerLabel = "";
  int cgTotal = 0;
  int currentWithGeo = 0;
  int inRadius = 0;

  void setStatus(GeoQueryStatus value) {
    if (status == value) return;
    status = value;
    notifyListeners();
  }

  void setLastError(String value) {
    lastError = value;
    notifyListeners();
  }

  void setCenter(GeoPoint center, {String source = "unknown"}) {
    centerKnown = true;
    centerLabel =
        "${center.latitude.toStringAsFixed(5)},${center.longitude.toStringAsFixed(5)} ($source)";
    notifyListeners();
  }

  void setCounts({
    required int cgTotal,
    required int currentWithGeo,
    required int inRadius,
  }) {
    this.cgTotal = cgTotal;
    this.currentWithGeo = currentWithGeo;
    this.inRadius = inRadius;
    notifyListeners();
  }
}

class GeoQueryService {
  GeoQueryService._({
    FirebaseFirestore? firestore,
    String? Function()? uidProvider,
    Future<GeoPoint?> Function()? deviceCenterLoader,
    Future<bool> Function()? locationAllowed,
    Future<Map<String, dynamic>?> Function(String)? profileLoader,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _uidProvider =
           uidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _deviceCenterLoader = deviceCenterLoader,
       _locationAllowed =
           locationAllowed ??
           (() async {
             await LocationPrivacyService.instance.ensureLoaded();
             return LocationPrivacyService.instance.mayReadLocation;
           }),
       _profileLoader = profileLoader;

  @visibleForTesting
  factory GeoQueryService.forTesting({
    required FirebaseFirestore firestore,
    required String? Function() uidProvider,
    required Future<GeoPoint?> Function() deviceCenterLoader,
    required Future<bool> Function() locationAllowed,
    Future<Map<String, dynamic>?> Function(String)? profileLoader,
  }) => GeoQueryService._(
    firestore: firestore,
    uidProvider: uidProvider,
    deviceCenterLoader: deviceCenterLoader,
    locationAllowed: locationAllowed,
    profileLoader: profileLoader,
  );

  static final GeoQueryService instance = GeoQueryService._();

  final GeoQueryDebug debug = GeoQueryDebug();

  final FirebaseFirestore _db;
  final String? Function() _uidProvider;
  final Future<GeoPoint?> Function()? _deviceCenterLoader;
  final Future<bool> Function() _locationAllowed;
  final Future<Map<String, dynamic>?> Function(String)? _profileLoader;
  int _sessionRevision = 0;

  void clearSession() {
    _sessionRevision++;
    debug.centerKnown = false;
    debug.centerLabel = "";
    debug.lastError = "";
    debug.status = GeoQueryStatus.idle;
    debug.setCounts(cgTotal: 0, currentWithGeo: 0, inRadius: 0);
  }

  @visibleForTesting
  static bool isPresenceLive({
    required DateTime? timestamp,
    required DateTime? expiresAt,
    DateTime? now,
  }) {
    if (timestamp == null || expiresAt == null) return false;
    final current = now ?? DateTime.now();
    if (!expiresAt.isAfter(current)) return false;

    final age = current.difference(timestamp);
    if (age < const Duration(minutes: -1)) return false;
    return age <= TTLPolicy.presenceCurrent;
  }

  Future<GeoPoint?> _resolveCenterFromCurrentUser(String uid) async {
    final snap = await _db
        .doc("users/$uid/presence/current")
        .get()
        .timeout(const Duration(seconds: 4));
    final data = snap.data() ?? const <String, dynamic>{};
    final gp = data["geopoint"];
    if (gp is GeoPoint &&
        isPresenceLive(
          timestamp: (data["ts"] as Timestamp?)?.toDate(),
          expiresAt: (data["expiresAt"] as Timestamp?)?.toDate(),
        )) {
      return gp;
    }
    return null;
  }

  Future<GeoPoint?> _resolveCenterFromDeviceLocation(
    bool Function() isCurrent, {
    required bool userInitiated,
  }) async {
    final result = await DeviceLocationResolver.instance.resolve(
      maxCachedAge: TTLPolicy.presenceCurrent,
      bypassFallbackCooldown: userInitiated,
      isCurrent: () =>
          isCurrent() && LocationPrivacyService.instance.mayReadLocation,
    );
    final pos = result.position;
    if (pos != null) return GeoPoint(pos.latitude, pos.longitude);
    if (isCurrent()) {
      debug.setLastError(
        'Device location: ${result.failure?.name ?? "unavailable"}',
      );
    }
    return null;
  }

  double _distanceMiles(GeoPoint a, GeoPoint b) {
    final lat1 = a.latitude;
    final lng1 = a.longitude;
    final lat2 = b.latitude;
    final lng2 = b.longitude;

    double deg2rad(double d) => d * (math.pi / 180.0);
    const rm = 3958.8;
    final dLat = deg2rad(lat2 - lat1);
    final dLon = deg2rad(lng2 - lng1);
    final la1 = deg2rad(lat1);
    final la2 = deg2rad(lat2);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLon / 2), 2);
    final dist = 2 * rm * math.asin(math.min(1.0, math.sqrt(h)));
    return dist;
  }

  String _uidFromPresencePath(String path) {
    // Expected path: users/{uid}/presence/current
    final parts = path.split("/");
    if (parts.length >= 4 && parts[0] == "users") {
      return parts[1];
    }
    return "";
  }

  Stream<List<NearbyDoc>> streamNearby({
    required GeoPoint? center,
    required double radiusMiles,
    int limitUsers = 50,
    bool userInitiated = false,
  }) async* {
    final meUid = _uidProvider() ?? "";
    final revision = _sessionRevision;
    bool isCurrent() =>
        meUid.isNotEmpty &&
        _uidProvider() == meUid &&
        _sessionRevision == revision;
    if (!isCurrent() || !radiusMiles.isFinite || radiusMiles <= 0) {
      yield const [];
      return;
    }
    debug.setLastError("");
    debug.setStatus(GeoQueryStatus.loading);
    if (!await _locationAllowed() || !isCurrent()) {
      if (isCurrent()) debug.setStatus(GeoQueryStatus.locationOff);
      yield const [];
      return;
    }
    GeoPoint? queryCenter = center;
    String centerSource = "provided";
    if (queryCenter == null) {
      try {
        final presenceCenter = await _resolveCenterFromCurrentUser(meUid);
        if (presenceCenter != null) {
          queryCenter = presenceCenter;
          centerSource = "presence";
        }
      } catch (e) {
        debug.setLastError("Failed to resolve center from presence: $e");
      }
    }

    if (!isCurrent()) {
      yield const [];
      return;
    }

    if (queryCenter == null) {
      try {
        queryCenter =
            await (_deviceCenterLoader?.call().timeout(
                  const Duration(seconds: 45),
                ) ??
                _resolveCenterFromDeviceLocation(
                  isCurrent,
                  userInitiated: userInitiated,
                ));
        if (queryCenter != null) {
          centerSource = "device";
        }
      } catch (e) {
        debug.setLastError("Failed to resolve center: $e");
      }
    }

    if (!isCurrent() || !await _locationAllowed() || !isCurrent()) {
      if (isCurrent()) debug.setStatus(GeoQueryStatus.locationOff);
      yield const [];
      return;
    }

    if (queryCenter == null) {
      debug.centerKnown = false;
      debug.centerLabel = "unknown";
      debug.setCounts(cgTotal: 0, currentWithGeo: 0, inRadius: 0);
      debug.setStatus(GeoQueryStatus.locationUnavailable);
      yield const <NearbyDoc>[];
      return;
    }

    debug.setCenter(queryCenter, source: centerSource);
    debug.setLastError("");

    final bounds = GeoQueryBounds.around(
      latitude: queryCenter.latitude,
      longitude: queryCenter.longitude,
      radiusMiles: radiusMiles,
    );
    Filter longitudeFilter(LongitudeRange range) => Filter.and(
      Filter('longitude', isGreaterThanOrEqualTo: range.west),
      Filter('longitude', isLessThanOrEqualTo: range.east),
    );
    final longitude = bounds.longitudes.length == 1
        ? longitudeFilter(bounds.longitudes.single)
        : Filter.or(
            longitudeFilter(bounds.longitudes[0]),
            longitudeFilter(bounds.longitudes[1]),
          );
    // Apply geographic filtering on the server BEFORE the candidate cap, so
    // distant users cannot crowd every local person out of discovery. One OR
    // query covers both sides of the date line without duplicate listeners.
    final presenceQuery = _db
        .collectionGroup("presence")
        .where(
          Filter.and(
            Filter('kind', isEqualTo: 'current'),
            Filter('latitude', isGreaterThanOrEqualTo: bounds.south),
            Filter('latitude', isLessThanOrEqualTo: bounds.north),
            longitude,
          ),
        )
        .orderBy('latitude')
        .orderBy('longitude')
        .limit((limitUsers * 3).clamp(50, 500));

    yield* presenceQuery
      .snapshots()
        .asyncMap((snap) async {
          if (!isCurrent() || !await _locationAllowed() || !isCurrent())
            return <NearbyDoc>[];
          final docs = snap.docs;
          int withGeo = 0;

          final results = await boundedAsyncMap(docs, (doc) async {
            if (!isCurrent()) return null;
            final data = doc.data();
            if (data["kind"] != "current") return null;
            final presenceTs = (data["ts"] as Timestamp?)?.toDate();
            final expiresAt = (data["expiresAt"] as Timestamp?)?.toDate();
            if (!isPresenceLive(timestamp: presenceTs, expiresAt: expiresAt)) {
              return null;
            }
            final gp = data["geopoint"];
            if (gp is! GeoPoint) return null;
            withGeo += 1;

            final uid = _uidFromPresencePath(doc.reference.path).trim();
            if (uid.isEmpty || uid == meUid) return null;

            final miles = _distanceMiles(queryCenter!, gp);
            if (miles > radiusMiles) return null;

            Map<String, dynamic> userData = const <String, dynamic>{};
            try {
              final loader = _profileLoader;
              final profile =
                  await (loader != null
                          ? loader(uid)
                          : _db
                                .doc("publicProfiles/$uid")
                                .get()
                                .then((snap) => snap.data()))
                      .timeout(const Duration(seconds: 4));
              if (!isCurrent() || profile == null) return null;
              userData = profile;
            } catch (error, stack) {
              // A failed profile read is not evidence that nobody is nearby.
              RuntimeDiagnosticsService.instance.record(
                error,
                stack,
                operation: 'Load nearby profile',
              );
              return null;
            }
            userData = <String, dynamic>{
              ...userData,
              "presence": Map<String, Object?>.from(data as Map),
            };

            return NearbyDoc(
              uid: uid,
              distanceMiles: miles,
              loc: gp,
              data: userData,
              presenceTs: presenceTs,
            );
          });

          if (!isCurrent() || !await _locationAllowed() || !isCurrent())
            return <NearbyDoc>[];
          final nearby = results.whereType<NearbyDoc>().toList();

          nearby.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
          debug.setCounts(
            cgTotal: docs.length,
            currentWithGeo: withGeo,
            inRadius: nearby.length,
          );
          debug.setStatus(GeoQueryStatus.ready);
          return nearby.take(limitUsers.clamp(1, 500)).toList(growable: false);
        })
        .handleError((Object error, StackTrace stack) {
          if (isCurrent()) {
            debug.setLastError('Nearby query failed (${error.runtimeType})');
            debug.setStatus(GeoQueryStatus.queryError);
            RuntimeDiagnosticsService.instance.record(
              error,
              stack,
              operation: 'Load nearby results',
            );
          }
          Error.throwWithStackTrace(error, stack);
        });
  }
}
