import "dart:async";
import "dart:math" as math;

import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/foundation.dart";
import "package:prox/services/user_settings_service.dart";

class DevSimNearbyDoc {
  const DevSimNearbyDoc({
    required this.uid,
    required this.geopoint,
    required this.distanceMiles,
    required this.data,
  });

  final String uid;
  final GeoPoint geopoint;
  final double distanceMiles;
  final Map<String, dynamic> data;
}

class DevUserSimulatorState {
  const DevUserSimulatorState({
    required this.enabled,
    required this.configuredCount,
    required this.onlineCount,
    required this.radiusMiles,
    required this.keywordOverlap,
    required this.onlineRatio,
    required this.mutualMatchChance,
    required this.tickSeconds,
    required this.lastTickAt,
  });

  static const DevUserSimulatorState initial = DevUserSimulatorState(
    enabled: false,
    configuredCount: 0,
    onlineCount: 0,
    radiusMiles: 2.0,
    keywordOverlap: 0.5,
    onlineRatio: 0.8,
    mutualMatchChance: 0.35,
    tickSeconds: 4,
    lastTickAt: null,
  );

  final bool enabled;
  final int configuredCount;
  final int onlineCount;
  final double radiusMiles;
  final double keywordOverlap;
  final double onlineRatio;
  final double mutualMatchChance;
  final int tickSeconds;
  final DateTime? lastTickAt;

  DevUserSimulatorState copyWith({
    bool? enabled,
    int? configuredCount,
    int? onlineCount,
    double? radiusMiles,
    double? keywordOverlap,
    double? onlineRatio,
    double? mutualMatchChance,
    int? tickSeconds,
    DateTime? lastTickAt,
  }) {
    return DevUserSimulatorState(
      enabled: enabled ?? this.enabled,
      configuredCount: configuredCount ?? this.configuredCount,
      onlineCount: onlineCount ?? this.onlineCount,
      radiusMiles: radiusMiles ?? this.radiusMiles,
      keywordOverlap: keywordOverlap ?? this.keywordOverlap,
      onlineRatio: onlineRatio ?? this.onlineRatio,
      mutualMatchChance: mutualMatchChance ?? this.mutualMatchChance,
      tickSeconds: tickSeconds ?? this.tickSeconds,
      lastTickAt: lastTickAt ?? this.lastTickAt,
    );
  }
}

class DevUserSimulatorService {
  DevUserSimulatorService._();
  static final DevUserSimulatorService instance = DevUserSimulatorService._();

  static const List<String> _sharedKeywordPool = <String>[
    "coffee",
    "fitness",
    "hiking",
    "networking",
    "startup",
    "music",
    "food",
    "art",
    "gaming",
    "tech",
  ];

  static const List<String> _uniqueKeywordPool = <String>[
    "book_club",
    "pet_lovers",
    "volunteer",
    "night_shift",
    "remote_work",
    "pickup_soccer",
    "dance",
    "photography",
    "board_games",
    "language_exchange",
    "open_mic",
    "yoga",
    "maker_space",
    "investing",
    "running",
  ];

  final ValueNotifier<DevUserSimulatorState> state =
      ValueNotifier<DevUserSimulatorState>(DevUserSimulatorState.initial);

  final math.Random _rng = math.Random();
  final Map<String, _SimUser> _users = <String, _SimUser>{};

  Timer? _timer;
  GeoPoint? _anchor;

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void configure({
    double? radiusMiles,
    double? keywordOverlap,
    double? onlineRatio,
    double? mutualMatchChance,
    int? tickSeconds,
  }) {
    state.value = state.value.copyWith(
      radiusMiles: _clamp01OrRange(radiusMiles, min: 0.2, max: 20.0, fallback: state.value.radiusMiles),
      keywordOverlap: _clamp01OrRange(keywordOverlap, min: 0.0, max: 1.0, fallback: state.value.keywordOverlap),
      onlineRatio: _clamp01OrRange(onlineRatio, min: 0.0, max: 1.0, fallback: state.value.onlineRatio),
      mutualMatchChance:
          _clamp01OrRange(mutualMatchChance, min: 0.0, max: 1.0, fallback: state.value.mutualMatchChance),
      tickSeconds: (tickSeconds ?? state.value.tickSeconds).clamp(2, 30),
    );

    if (_users.isNotEmpty) {
      _reseedKeywords();
    }

    if (state.value.enabled) {
      _restartTimer();
    }
  }

  void spawnPreset(int count, {GeoPoint? around}) {
    final int safeCount = count.clamp(1, 50);
    if (around != null) {
      _anchor = around;
    }

    state.value = state.value.copyWith(
      enabled: true,
      configuredCount: safeCount,
    );

    _buildPopulationIfPossible(forceRebuild: true);
    _restartTimer();
    _tick();
  }

  void setRunning(bool running) {
    if (!running) {
      stop();
      return;
    }

    state.value = state.value.copyWith(enabled: true);
    _buildPopulationIfPossible(forceRebuild: false);
    _restartTimer();
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _users.clear();
    state.value = state.value.copyWith(
      enabled: false,
      configuredCount: 0,
      onlineCount: 0,
      lastTickAt: DateTime.now(),
    );
  }

  void resetAnchor() {
    _anchor = null;
  }

  List<DevSimNearbyDoc> queryNearby({
    required GeoPoint center,
    required double radiusMiles,
    required String excludeUid,
  }) {
    final allowInDemo = UserSettingsService.instance.current.demoModeEnabled;
    if (!kDebugMode && !allowInDemo) return const <DevSimNearbyDoc>[];
    if (!state.value.enabled) return const <DevSimNearbyDoc>[];

    _anchor ??= center;
    _buildPopulationIfPossible(forceRebuild: false);

    final DateTime now = DateTime.now();
    final List<DevSimNearbyDoc> out = <DevSimNearbyDoc>[];

    for (final entry in _users.entries) {
      final uid = entry.key;
      final u = entry.value;
      if (!u.isOnline) continue;
      if (uid == excludeUid) continue;

      final double miles = _haversineMiles(
        center.latitude,
        center.longitude,
        u.lat,
        u.lng,
      );

      if (miles > radiusMiles) continue;

      final bool mutualRoll = _rng.nextDouble() <= state.value.mutualMatchChance;

      out.add(
        DevSimNearbyDoc(
          uid: uid,
          geopoint: GeoPoint(u.lat, u.lng),
          distanceMiles: miles,
          data: <String, dynamic>{
            "geopoint": GeoPoint(u.lat, u.lng),
            "lat": u.lat,
            "lon": u.lng,
            "displayName": u.displayName,
            "name": u.displayName,
            "keywords": <String, dynamic>{
              "Searching For": u.searchingFor,
              "Can Provide": u.canProvide,
            },
            "isBusiness": false,
            "businessEnabled": false,
            "availabilityMinutes": 0,
            "online": true,
            "simulated": true,
            "sim_mutualRoll": mutualRoll,
            "sim_session": "in_app",
            "ts": Timestamp.fromDate(now),
            "expiresAt": Timestamp.fromDate(now.add(const Duration(minutes: 8))),
          },
        ),
      );
    }

    out.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
    return out;
  }

  void updateAnchorFromCenter(GeoPoint center) {
    _anchor ??= center;
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: state.value.tickSeconds),
      (_) => _tick(),
    );
  }

  void _buildPopulationIfPossible({required bool forceRebuild}) {
    if (!state.value.enabled) return;
    if (_anchor == null) return;

    final int count = state.value.configuredCount;
    if (count <= 0) return;

    if (!forceRebuild && _users.length == count) return;

    _users.clear();
    for (int i = 0; i < count; i++) {
      final uid = "sim_${DateTime.now().millisecondsSinceEpoch}_${i.toString().padLeft(2, "0")}";
      final point = _randomPointAround(_anchor!, state.value.radiusMiles);
      final keywords = _buildKeywordGroups(i);
      _users[uid] = _SimUser(
        uid: uid,
        displayName: "Sim User ${i + 1}",
        lat: point.latitude,
        lng: point.longitude,
        orbitMiles: _rng.nextDouble() * state.value.radiusMiles,
        headingRad: _rng.nextDouble() * math.pi * 2,
        driftMiles: 0.03 + _rng.nextDouble() * 0.09,
        searchingFor: keywords.$1,
        canProvide: keywords.$2,
        isOnline: _rng.nextDouble() <= state.value.onlineRatio,
      );
    }

    _updateOnlineCount();
  }

  void _reseedKeywords() {
    int i = 0;
    for (final entry in _users.entries) {
      final keywords = _buildKeywordGroups(i);
      entry.value.searchingFor
        ..clear()
        ..addAll(keywords.$1);
      entry.value.canProvide
        ..clear()
        ..addAll(keywords.$2);
      i++;
    }
  }

  void _tick() {
    if (!state.value.enabled) return;
    if (_anchor == null) return;
    if (_users.isEmpty) return;

    final GeoPoint anchor = _anchor!;

    for (final user in _users.values) {
      user.headingRad += (_rng.nextDouble() - 0.5) * 0.8;
      final step = user.driftMiles;
      final dLat = (step / 69.0) * math.cos(user.headingRad);
      final lonScale = math.max(0.01, math.cos(anchor.latitude * math.pi / 180.0));
      final dLng = (step / (69.0 * lonScale)) * math.sin(user.headingRad);

      user.lat += dLat;
      user.lng += dLng;

      final currentRadius = _haversineMiles(anchor.latitude, anchor.longitude, user.lat, user.lng);
      if (currentRadius > state.value.radiusMiles) {
        final pulled = _randomPointAround(anchor, state.value.radiusMiles * 0.92);
        user.lat = pulled.latitude;
        user.lng = pulled.longitude;
      }

      final onlineFlipRoll = _rng.nextDouble();
      if (onlineFlipRoll < 0.25) {
        user.isOnline = _rng.nextDouble() <= state.value.onlineRatio;
      }
    }

    _updateOnlineCount();
    state.value = state.value.copyWith(lastTickAt: DateTime.now());
  }

  void _updateOnlineCount() {
    final int online = _users.values.where((u) => u.isOnline).length;
    state.value = state.value.copyWith(onlineCount: online);
  }

  (List<String>, List<String>) _buildKeywordGroups(int index) {
    final int overlapCount = (1 + (state.value.keywordOverlap * 3)).round().clamp(1, 4);
    final int uniqueCount = 2;

    final List<String> searching = <String>[];
    final List<String> provide = <String>[];

    for (int i = 0; i < overlapCount; i++) {
      searching.add(_sharedKeywordPool[(index + i) % _sharedKeywordPool.length]);
      provide.add(_sharedKeywordPool[(index + i + 3) % _sharedKeywordPool.length]);
    }

    for (int i = 0; i < uniqueCount; i++) {
      searching.add(_uniqueKeywordPool[_rng.nextInt(_uniqueKeywordPool.length)]);
      provide.add(_uniqueKeywordPool[_rng.nextInt(_uniqueKeywordPool.length)]);
    }

    return (_dedupe(searching), _dedupe(provide));
  }

  GeoPoint _randomPointAround(GeoPoint center, double radiusMiles) {
    final double r = radiusMiles * math.sqrt(_rng.nextDouble());
    final double t = 2 * math.pi * _rng.nextDouble();

    final double dLat = (r / 69.0) * math.cos(t);
    final double lonScale = math.max(0.01, math.cos(center.latitude * math.pi / 180.0));
    final double dLng = (r / (69.0 * lonScale)) * math.sin(t);

    return GeoPoint(center.latitude + dLat, center.longitude + dLng);
  }

  List<String> _dedupe(List<String> items) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in items) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      if (!seen.add(s)) continue;
      out.add(s);
    }
    return out;
  }

  double _clamp01OrRange(double? v, {required double min, required double max, required double fallback}) {
    if (v == null) return fallback;
    if (v.isNaN || v.isInfinite) return fallback;
    return v.clamp(min, max).toDouble();
  }

  double _haversineMiles(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusMiles = 3958.7613;
    double rad(double d) => d * math.pi / 180.0;

    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMiles * c;
  }
}

class _SimUser {
  _SimUser({
    required this.uid,
    required this.displayName,
    required this.lat,
    required this.lng,
    required this.orbitMiles,
    required this.headingRad,
    required this.driftMiles,
    required this.searchingFor,
    required this.canProvide,
    required this.isOnline,
  });

  final String uid;
  final String displayName;
  double lat;
  double lng;
  double orbitMiles;
  double headingRad;
  double driftMiles;
  final List<String> searchingFor;
  final List<String> canProvide;
  bool isOnline;
}
