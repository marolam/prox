import "dart:async";
import "package:flutter/foundation.dart";
import "package:prox/models/user_settings.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/services/matching/matching_runtime_service.dart";
import "package:prox/services/user_settings_service.dart";

class NearbyBootstrapDebugState {
  const NearbyBootstrapDebugState({
    this.started = false,
    this.centerKnown = false,
    this.centerLabel = "",
    this.lastError = "",
    this.lastHits = 0,
    this.lastEnsureUid = "",
    this.lastEnsureAt,
    this.cgTotal = 0,
    this.currentWithGeo = 0,
    this.inRadius = 0,
  });

  final bool started;
  final bool centerKnown;
  final String centerLabel;
  final String lastError;
  final int lastHits;
  final String lastEnsureUid;
  final DateTime? lastEnsureAt;
  final int cgTotal;
  final int currentWithGeo;
  final int inRadius;

  NearbyBootstrapDebugState copyWith({
    bool? started,
    bool? centerKnown,
    String? centerLabel,
    String? lastError,
    int? lastHits,
    String? lastEnsureUid,
    DateTime? lastEnsureAt,
    int? cgTotal,
    int? currentWithGeo,
    int? inRadius,
  }) {
    return NearbyBootstrapDebugState(
      started: started ?? this.started,
      centerKnown: centerKnown ?? this.centerKnown,
      centerLabel: centerLabel ?? this.centerLabel,
      lastError: lastError ?? this.lastError,
      lastHits: lastHits ?? this.lastHits,
      lastEnsureUid: lastEnsureUid ?? this.lastEnsureUid,
      lastEnsureAt: lastEnsureAt ?? this.lastEnsureAt,
      cgTotal: cgTotal ?? this.cgTotal,
      currentWithGeo: currentWithGeo ?? this.currentWithGeo,
      inRadius: inRadius ?? this.inRadius,
    );
  }
}

class NearbyBootstrap {
  NearbyBootstrap._();

  static final NearbyBootstrap instance = NearbyBootstrap._();
  static final ValueNotifier<NearbyBootstrapDebugState> debug =
      ValueNotifier<NearbyBootstrapDebugState>(
    const NearbyBootstrapDebugState(),
  );

  bool isRunning = false;
  StreamSubscription<List<NearbyDoc>>? _sub;
  final Set<String> _known = <String>{};
  final Map<String, DateTime> _recentlyPinged = <String, DateTime>{};
  final Duration _cooldown = const Duration(minutes: 5);

  Future<void> start({double radiusMiles = 2.0, int limitUsers = 50}) async {
    stop();
    isRunning = true;
    debug.value = debug.value.copyWith(
      started: true,
      lastError: "",
      lastHits: 0,
      lastEnsureUid: "",
      lastEnsureAt: null,
      cgTotal: 0,
      currentWithGeo: 0,
      inRadius: 0,
    );

    _sub = GeoQueryService.instance
        .streamNearby(center: null, radiusMiles: radiusMiles, limitUsers: limitUsers)
        .listen(
      (nearby) {
        final ids = nearby.map((d) => d.uid).toSet();
        final entrants = ids.difference(_known).toList(growable: false);

        _known
          ..clear()
          ..addAll(ids);

        final now = DateTime.now();
        String lastEnsuredUid = "";
        for (final uid in entrants) {
          final last = _recentlyPinged[uid];
          final cooled = last == null || now.difference(last) > _cooldown;
          if (!cooled) continue;
          _recentlyPinged[uid] = now;
          lastEnsuredUid = uid;
        }

        final qd = GeoQueryService.instance.debug;
        debug.value = debug.value.copyWith(
          started: true,
          centerKnown: qd.centerKnown,
          centerLabel: qd.centerLabel,
          lastError: qd.lastError,
          lastHits: nearby.length,
          lastEnsureUid: lastEnsuredUid.isEmpty ? debug.value.lastEnsureUid : lastEnsuredUid,
          lastEnsureAt: lastEnsuredUid.isEmpty ? debug.value.lastEnsureAt : now,
          cgTotal: qd.cgTotal,
          currentWithGeo: qd.currentWithGeo,
          inRadius: qd.inRadius,
        );
      },
      onError: (Object e) {
        debug.value = debug.value.copyWith(lastError: e.toString());
      },
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    isRunning = false;
    _known.clear();
    _recentlyPinged.clear();
    debug.value = debug.value.copyWith(started: false);
  }

  void dispose() {
    stop();
  }
}

Future<void> proxBootstrapNearby() async {
  await UserSettingsService.instance.ensureLoaded();
  final MatchDiscoverySettings discovery =
      UserSettingsService.instance.current.matchDiscovery;
  final radiusMiles = MatchingRuntimeService.instance.effectiveRadiusMiles(discovery);
  await NearbyBootstrap.instance.start(radiusMiles: radiusMiles, limitUsers: 200);
}

Future<void> proxRestartNearby() async {
  NearbyBootstrap.instance.stop();
  await proxBootstrapNearby();
}
