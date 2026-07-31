import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:geolocator/geolocator.dart";
import "dart:math" as math;

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

  bool get isBusiness => data["isBusiness"] == true || data["businessMode"] == true;

  int? get availabilityMinutes => (data["availabilityMinutes"] as num?)?.toInt();
}

class GeoQueryDebug extends ChangeNotifier {
  String lastError = "";
  bool centerKnown = false;
  String centerLabel = "";
  int cgTotal = 0;
  int currentWithGeo = 0;
  int inRadius = 0;

  void setLastError(String value) {
    lastError = value;
    notifyListeners();
  }

  void setCenter(GeoPoint center, {String source = "unknown"}) {
    centerKnown = true;
    centerLabel = "${center.latitude.toStringAsFixed(5)},${center.longitude.toStringAsFixed(5)} ($source)";
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
  GeoQueryService._();

  static final GeoQueryService instance = GeoQueryService._();

  final GeoQueryDebug debug = GeoQueryDebug();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<({GeoPoint point, DateTime? ts})?> _resolveCenterFromCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;

    final snap = await _db.doc("users/$uid/presence/current").get();
    final data = snap.data() ?? const <String, dynamic>{};
    final gp = data["geopoint"];
    if (gp is GeoPoint) {
      return (
        point: gp,
        ts: (data["ts"] as Timestamp?)?.toDate(),
      );
    }
    return null;
  }

  bool _presenceCenterFresh(DateTime? ts) {
    if (ts == null) return true;
    return DateTime.now().difference(ts).abs() <= const Duration(minutes: 10);
  }

  Future<GeoPoint?> _resolveCenterFromDeviceLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
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
    final h = math.pow(math.sin(dLat / 2), 2) +
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
  }) async* {
    GeoPoint? queryCenter = center;
    String centerSource = "provided";
    if (queryCenter == null) {
      try {
        final presenceCenter = await _resolveCenterFromCurrentUser();
        if (presenceCenter != null && _presenceCenterFresh(presenceCenter.ts)) {
          queryCenter = presenceCenter.point;
          centerSource = "presence";
        }
      } catch (e) {
        debug.setLastError("Failed to resolve center from presence: $e");
      }
    }

    if (queryCenter == null) {
      try {
        queryCenter = await _resolveCenterFromDeviceLocation();
        if (queryCenter != null) {
          centerSource = "device";
        }
      } catch (e) {
        debug.setLastError("Failed to resolve center: $e");
      }
    }

    if (queryCenter == null) {
      debug.centerKnown = false;
      debug.centerLabel = "unknown";
      debug.setCounts(cgTotal: 0, currentWithGeo: 0, inRadius: 0);
      debug.setLastError("No /users/{uid}/presence/current geopoint found");
      yield const <NearbyDoc>[];
      return;
    }

    debug.setCenter(queryCenter, source: centerSource);
    debug.setLastError("");

    final meUid = FirebaseAuth.instance.currentUser?.uid ?? "";

    yield* _db
        .collectionGroup("presence")
        .where("kind", isEqualTo: "current")
        .limit(limitUsers.clamp(1, 500))
        .snapshots()
        .handleError((Object e) {
          debug.setLastError("presence query failed: $e");
        })
        .asyncMap((snap) async {
      final docs = snap.docs;
      final nearby = <NearbyDoc>[];
      int withGeo = 0;

      for (final doc in docs) {
        final data = doc.data();
        final gp = data["geopoint"];
        if (gp is! GeoPoint) continue;
        withGeo += 1;

        final uid = _uidFromPresencePath(doc.reference.path).trim();
        if (uid.isEmpty) continue;
        if (meUid.isNotEmpty && uid == meUid) continue;

        final miles = _distanceMiles(queryCenter!, gp);
        if (miles > radiusMiles) continue;

        Map<String, dynamic> userData = const <String, dynamic>{};
        try {
          final userSnap = await _db.doc("users/$uid").get();
          userData = userSnap.data() ?? const <String, dynamic>{};
        } catch (_) {
          // Keep nearby row even if user profile fetch fails.
        }

        nearby.add(
          NearbyDoc(
            uid: uid,
            distanceMiles: miles,
            loc: gp,
            data: userData,
            presenceTs: (data["ts"] as Timestamp?)?.toDate(),
          ),
        );
      }

      nearby.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
      debug.setCounts(
        cgTotal: docs.length,
        currentWithGeo: withGeo,
        inRadius: nearby.length,
      );
      return nearby;
    });
  }
}
