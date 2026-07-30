import "dart:async";

import "package:prox/models/user_settings.dart";
import "package:prox/services/device_storage_service.dart";

class UserSettingsService {
  UserSettingsService._();
  static final UserSettingsService instance = UserSettingsService._();

  static const String _storageKey = "user_settings";

  UserSettings _settings = const UserSettings.defaults();
  final StreamController<UserSettings> _controller =
      StreamController<UserSettings>.broadcast();

  bool _loadedFromStorage = false;
  bool _ensureLoadQueued = false;

  UserSettings get current => _settings;

  Future<void> ensureLoaded() async {
    if (_loadedFromStorage) return;
    _loadedFromStorage = true;

    await DeviceStorageService.instance.load();
    final raw = DeviceStorageService.instance.get(_storageKey);
    if (raw != null) {
      try {
        final loaded = UserSettings.fromJson(raw);
        _settings = loaded;
      } catch (_) {
        _settings = const UserSettings.defaults();
      }
    }
    _emit(_settings, persist: false);
  }

  Stream<UserSettings> watch() {
    if (!_loadedFromStorage && !_ensureLoadQueued) {
      _ensureLoadQueued = true;
      _ensureLoadedAsync();
    }

    scheduleMicrotask(() {
      if (!_controller.isClosed) {
        _controller.add(_settings);
      }
    });
    return _controller.stream;
  }

  void _ensureLoadedAsync() {
    // ignore: discarded_futures
    ensureLoaded();
  }

  void _emit(UserSettings next, {bool persist = true}) {
    if (identical(next, _settings)) return;
    _settings = next;
    if (!_controller.isClosed) {
      _controller.add(_settings);
    }
    if (persist) {
      // ignore: discarded_futures
      DeviceStorageService.instance.set(
        _storageKey,
        _settings.toJson(),
      );
    }
  }

  void updateMatchDiscovery(MatchDiscoverySettings discovery) {
    _emit(_settings.copyWith(matchDiscovery: discovery));
  }

  void setMatchingMode(MatchingModeKind mode) {
    final cur = _settings.matchDiscovery;
    if (cur.modeKind == mode) return;
    _emit(_settings.copyWith(matchDiscovery: cur.copyWith(modeKind: mode)));
  }

  void setNormalMatchMode(NormalMatchMode mode) {
    final cur = _settings.matchDiscovery;
    if (cur.normalMode == mode) return;
    _emit(_settings.copyWith(matchDiscovery: cur.copyWith(normalMode: mode)));
  }

  void setTreasureRadiusMiles(double miles) {
    final safe = miles
        .clamp(MatchDiscoverySettings.minRadiusMiles, MatchDiscoverySettings.maxRadiusMiles)
        .toDouble();
    final cur = _settings.matchDiscovery;
    if (cur.treasureRadiusMiles == safe) return;
    _emit(_settings.copyWith(matchDiscovery: cur.copyWith(treasureRadiusMiles: safe)));
  }

  void setRadiusMiles(double miles) {
    final cur = _settings.matchDiscovery;
    final maxAllowed = MatchDiscoverySettings.allowedMaxRadiusMiles(
      highRadiusUnlocked: cur.highRadiusUnlocked,
      businessOnly: cur.businessOnly,
      modeKind: cur.modeKind,
      normalMode: cur.normalMode,
    );
    final safe = miles
        .clamp(MatchDiscoverySettings.minRadiusMiles, maxAllowed)
        .toDouble();
    if (cur.radiusMiles == safe) return;
    _emit(_settings.copyWith(matchDiscovery: cur.copyWith(radiusMiles: safe)));
  }

  void setHighRadiusUnlocked(bool unlocked) {
    final cur = _settings.matchDiscovery;
    if (cur.highRadiusUnlocked == unlocked) return;

    final updated = cur.copyWith(highRadiusUnlocked: unlocked);
    final maxAllowed = MatchDiscoverySettings.allowedMaxRadiusMiles(
      highRadiusUnlocked: updated.highRadiusUnlocked,
      businessOnly: updated.businessOnly,
      modeKind: updated.modeKind,
      normalMode: updated.normalMode,
    );
    final clampedRadius = updated.radiusMiles.clamp(
      MatchDiscoverySettings.minRadiusMiles,
      maxAllowed,
    );

    _emit(
      _settings.copyWith(
        matchDiscovery: updated.copyWith(radiusMiles: clampedRadius.toDouble()),
      ),
    );
  }

  void setSingleKeywordMatchUnlocked(bool unlocked) {
    final cur = _settings.matchDiscovery;
    if (cur.singleKeywordMatchUnlocked == unlocked) return;
    _emit(
      _settings.copyWith(
        matchDiscovery: cur.copyWith(singleKeywordMatchUnlocked: unlocked),
      ),
    );
  }

  void setReciprocalMatchUnlocked(bool unlocked) {
    final cur = _settings.matchDiscovery;
    if (cur.reciprocalMatchUnlocked == unlocked) return;
    _emit(
      _settings.copyWith(
        matchDiscovery: cur.copyWith(reciprocalMatchUnlocked: unlocked),
      ),
    );
  }

  void setKeywordChainUnlocked(bool unlocked) {
    final cur = _settings.matchDiscovery;
    if (cur.keywordChainUnlocked == unlocked) return;
    _emit(
      _settings.copyWith(
        matchDiscovery: cur.copyWith(keywordChainUnlocked: unlocked),
      ),
    );
  }

  void recordActiveModePenalty({
    required Duration lockDuration,
  }) {
    final cur = _settings.matchDiscovery;
    final lockUntil = DateTime.now().add(lockDuration).millisecondsSinceEpoch;
    final next = cur.copyWith(
      normalMode: NormalMatchMode.passive,
      activePenaltyCount: cur.activePenaltyCount + 1,
      activeLockUntilEpochMs: lockUntil,
    );
    _emit(_settings.copyWith(matchDiscovery: next));
  }

  void setActiveLockFromServer({
    required int lockUntilEpochMs,
    required int penaltyCount,
  }) {
    final cur = _settings.matchDiscovery;
    final int normalizedLock = lockUntilEpochMs < 0 ? 0 : lockUntilEpochMs;
    final int normalizedPenalty = penaltyCount < 0 ? 0 : penaltyCount;

    final next = cur.copyWith(
      normalMode: normalizedLock > DateTime.now().millisecondsSinceEpoch
          ? NormalMatchMode.passive
          : cur.normalMode,
      activeLockUntilEpochMs: normalizedLock,
      activePenaltyCount: normalizedPenalty,
    );

    _emit(_settings.copyWith(matchDiscovery: next));
  }

  void clearActiveLockIfExpired() {
    final cur = _settings.matchDiscovery;
    if (!cur.isActiveLocked && cur.activeLockUntilEpochMs != 0) {
      final next = cur.copyWith(activeLockUntilEpochMs: 0);
      _emit(_settings.copyWith(matchDiscovery: next));
    }
  }

  // Persona mode (Party  Business)
  void setUxMode(AppUxMode mode) {
    if (_settings.uxMode == mode) return;
    _emit(_settings.copyWith(uxMode: mode));
  }

  void markModeExplainerSeen() {
    if (_settings.hasSeenModeExplainer) return;
    _emit(_settings.copyWith(hasSeenModeExplainer: true));
  }

  // Pillar #3 cosmetics selections
  void setPartyCosmetic(String packId) {
    final p = packId.trim().isEmpty ? "default" : packId.trim();
    if (_settings.partyCosmeticPackId == p) return;
    _emit(_settings.copyWith(partyCosmeticPackId: p));
  }

  void setBusinessCosmetic(String packId) {
    final p = packId.trim().isEmpty ? "default" : packId.trim();
    if (_settings.businessCosmeticPackId == p) return;
    _emit(_settings.copyWith(businessCosmeticPackId: p));
  }

  // Suggestion #3 toggle
  void setTrustPulseEnabled(bool enabled) {
    if (_settings.trustPulseEnabled == enabled) return;
    _emit(_settings.copyWith(trustPulseEnabled: enabled));
  }

  // Suggestion #2 toggle
  void setReferralSignalEnabled(bool enabled) {
    if (_settings.referralSignalEnabled == enabled) return;
    _emit(_settings.copyWith(referralSignalEnabled: enabled));
  }

  void setDemoModeEnabled(bool enabled) {
    if (_settings.demoModeEnabled == enabled) return;
    _emit(_settings.copyWith(demoModeEnabled: enabled));
  }

  void setDemoSimulatedNearbyLocationEnabled(bool enabled) {
    if (_settings.demoSimulatedNearbyLocationEnabled == enabled) return;
    _emit(_settings.copyWith(demoSimulatedNearbyLocationEnabled: enabled));
  }

  void setDemoSimulatedNearbyOffsetMiles(double miles) {
    final safe = miles.clamp(0.0, 1.0).toDouble();
    if (_settings.demoSimulatedNearbyOffsetMiles == safe) return;
    _emit(_settings.copyWith(demoSimulatedNearbyOffsetMiles: safe));
  }

  void setDemoForceMatchAllWithinRadius(bool enabled) {
    if (_settings.demoForceMatchAllWithinRadius == enabled) return;
    _emit(_settings.copyWith(demoForceMatchAllWithinRadius: enabled));
  }

  void setDemoFastPresenceRefreshEnabled(bool enabled) {
    if (_settings.demoFastPresenceRefreshEnabled == enabled) return;
    _emit(_settings.copyWith(demoFastPresenceRefreshEnabled: enabled));
  }

  void setTextScaleFactor(double value) {
    final safe = value.clamp(0.9, 1.6).toDouble();
    if (_settings.textScaleFactor == safe) return;
    _emit(_settings.copyWith(textScaleFactor: safe));
  }

  void setSimpleModeEnabled(bool enabled) {
    if (_settings.simpleModeEnabled == enabled) return;
    _emit(_settings.copyWith(simpleModeEnabled: enabled));
  }

  void setSimpleModeCompleted(bool completed) {
    if (_settings.simpleModeCompleted == completed) return;
    _emit(_settings.copyWith(simpleModeCompleted: completed));
  }

  void setSimpleModeStageIndex(int stageIndex) {
    final safe = stageIndex < 0 ? 0 : stageIndex;
    if (_settings.simpleModeStageIndex == safe) return;
    _emit(_settings.copyWith(simpleModeStageIndex: safe));
  }

  void markBusinessIntroSeen() {
    if (_settings.hasSeenBusinessIntro) return;
    _emit(_settings.copyWith(hasSeenBusinessIntro: true));
  }

  void markBusinessFilterHintSeen() {
    if (_settings.hasSeenBusinessFilterHint) return;
    _emit(_settings.copyWith(hasSeenBusinessFilterHint: true));
  }

  void markBusinessReactivateSeen() {
    if (_settings.hasSeenBusinessReactivate) return;
    _emit(_settings.copyWith(hasSeenBusinessReactivate: true));
  }

  void setBusinessAvatarEnabled(bool enabled) {
    if (_settings.businessAvatarEnabled == enabled) return;
    _emit(_settings.copyWith(businessAvatarEnabled: enabled));
  }

  void setBusinessAvatarNote(String? note) {
    final trimmed = note?.trim();
    if (_settings.businessAvatarNote == trimmed) return;
    _emit(_settings.copyWith(businessAvatarNote: trimmed));
  }

  bool hasSeenBusinessPromptFor(String otherUid) {
    final map = _settings.seenBusinessPrompts;
    if (map.isEmpty) return false;
    return map[otherUid] == true;
  }

  void markBusinessPromptSeenFor(String otherUid) {
    final current = _settings.seenBusinessPrompts;
    if (current[otherUid] == true) return;

    final nextMap = <String, bool>{}
      ..addAll(current)
      ..[otherUid] = true;

    _emit(_settings.copyWith(seenBusinessPrompts: nextMap));
  }

  bool hasSeenTreePublicEligibleNudge() {
    return _settings.hasSeenTreePublicEligibleNudge;
  }

  void markTreePublicEligibleNudgeSeen() {
    if (_settings.hasSeenTreePublicEligibleNudge) return;
    _emit(_settings.copyWith(hasSeenTreePublicEligibleNudge: true));
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
