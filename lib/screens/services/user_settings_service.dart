import "dart:async";
import "package:flutter/foundation.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/device_storage_service.dart";
import "package:prox/services/pro_mode_preview_access.dart";
import "package:prox/services/runtime_diagnostics_service.dart";

class UserSettingsService {
  UserSettingsService._({
    Future<void> Function(UserSettings)? persistSettings,
    bool Function()? proPreviewAllowed,
  }) : _persistSettings = persistSettings,
       _proPreviewAllowed = proPreviewAllowed;
  @visibleForTesting
  factory UserSettingsService.forTesting({
    UserSettings initial = const UserSettings.defaults(),
    Future<void> Function(UserSettings)? persistSettings,
    bool Function()? proPreviewAllowed,
  }) =>
      UserSettingsService._(
          persistSettings: persistSettings ?? (_) async {},
          proPreviewAllowed: proPreviewAllowed,
        )
        .._settings = initial
        .._loadedFromStorage = true;
  static final UserSettingsService instance = UserSettingsService._();
  final Future<void> Function(UserSettings)? _persistSettings;
  final bool Function()? _proPreviewAllowed;

  static const String _storageKey = "user_settings";

  UserSettings _settings = const UserSettings.defaults();
  final StreamController<UserSettings> _controller =
      StreamController<UserSettings>.broadcast();

  bool _loadedFromStorage = false;
  bool _ensureLoadQueued = false;
  Future<void>? _loading;
  int _revision = 0;
  Future<void> _persisting = Future<void>.value();
  String? _settingsOwnerUid;
  bool _entitlementsManaged = false;
  Map<String, dynamic> _paidEntitlements = const {};

  UserSettings get current => _settings;

  Future<void> _persist(UserSettings settings) {
    final snapshot = {...settings.toJson(), '_accountUid': _settingsOwnerUid};
    return _persisting = _persisting
        .catchError((Object _) {})
        .then(
          (_) => _persistSettings != null
              ? _persistSettings(settings)
              : DeviceStorageService.instance.set(_storageKey, snapshot),
        );
  }

  /// Starts an account-scoped entitlement session. Device appearance preferences
  /// survive a switch; private notes, peer prompt history and paid access do not.
  Future<void> bindAccountSession(String? uid) {
    _revision++;
    final clearPrivate = uid == null || _settingsOwnerUid != uid;
    _settingsOwnerUid = uid;
    _entitlementsManaged = true;
    _paidEntitlements = const {};
    _loadedFromStorage = true;
    var next = _settings;
    if (clearPrivate) {
      next = UserSettings.fromJson({
        ...next.toJson(),
        'businessAvatarNote': null,
        'businessAvatarEnabled': false,
        'seenBusinessPrompts': <String, bool>{},
        'uxMode': AppUxMode.party.name,
      });
    }
    _emit(next.copyWith(), persist: false);
    return _persist(_settings);
  }

  /// A single snapshot updates every paid matching flag and clamps currently
  /// selected controls. Legacy setters cannot overwrite this server snapshot.
  void applyBillingEntitlements(String uid, Map<String, dynamic>? data) {
    if (!_entitlementsManaged || _settingsOwnerUid != uid) return;
    _paidEntitlements = Map.unmodifiable(data ?? const <String, dynamic>{});
    final next = _withBillingEntitlements(_settings, _paidEntitlements);
    if (next == _settings) return;
    _emit(next);
  }

  UserSettings _withBillingEntitlements(
    UserSettings settings,
    Map<String, dynamic> data,
  ) {
    final cur = settings.matchDiscovery;
    final highRadius = data['highRadiusUnlocked'] == true;
    final single = data['singleKeywordMatchModeUnlocked'] == true;
    final reciprocal = data['reciprocalKeywordMatchModeUnlocked'] == true;
    final chain = data['keywordChainMatchModeUnlocked'] == true;
    final keywordAllowed = switch (cur.keywordMode) {
      KeywordMatchMode.singleKeyword => single,
      KeywordMatchMode.reciprocalOpposite => reciprocal,
      KeywordMatchMode.keywordChain => chain,
      _ => true,
    };
    final maxRadius = MatchDiscoverySettings.allowedMaxRadiusMiles(
      highRadiusUnlocked: highRadius,
      businessOnly: cur.businessOnly,
      modeKind: cur.modeKind,
      normalMode: cur.normalMode,
    );
    return settings.copyWith(
      matchDiscovery: cur.copyWith(
        highRadiusUnlocked: highRadius,
        singleKeywordMatchUnlocked: single,
        reciprocalMatchUnlocked: reciprocal,
        keywordChainUnlocked: chain,
        keywordMode: keywordAllowed
            ? cur.keywordMode
            : KeywordMatchMode.similar,
        radiusMiles: cur.radiusMiles
            .clamp(MatchDiscoverySettings.minRadiusMiles, maxRadius)
            .toDouble(),
      ),
    );
  }

  /// Clears device-local account notes and settings once deletion is confirmed.
  Future<void> resetAfterAccountDeletion() {
    _revision++;
    _loadedFromStorage = true;
    _settings = const UserSettings.defaults();
    _settingsOwnerUid = null;
    _paidEntitlements = const {};
    if (!_controller.isClosed) _controller.add(_settings);
    return _persist(_settings);
  }

  bool get canUseProModePreview =>
      _proPreviewAllowed?.call() ??
      ProModePreviewAccess.instance.isAllowedForCurrentUser();

  Future<void> ensureLoaded() {
    if (_loadedFromStorage) return Future<void>.value();
    return _loading ??= _loadSettings();
  }

  Future<void> _loadSettings() async {
    final revisionAtStart = _revision;
    try {
      await DeviceStorageService.instance.load();
      final raw = DeviceStorageService.instance.get(_storageKey);
      if (raw != null && revisionAtStart == _revision) {
        try {
          final loaded = UserSettings.fromJson(raw);
          _settingsOwnerUid = raw is Map ? raw['_accountUid'] as String? : null;
          // Persisted paid flags are never evidence of current server access.
          final normalized = _withBillingEntitlements(
            _normalizeProModeAccess(loaded),
            const {},
          );
          _settings = normalized;
          if (normalized != loaded) {
            await _persist(normalized);
          }
        } catch (_) {
          _settings = const UserSettings.defaults();
        }
      }
      _loadedFromStorage = true;
      // Loading previously emitted the identical object, which _emit suppressed.
      if (!_controller.isClosed) _controller.add(_settings);
    } finally {
      _loading = null;
      _ensureLoadQueued = false;
    }
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
    unawaited(
      ensureLoaded().catchError((Object _) {
        _ensureLoadQueued = false;
      }),
    );
  }

  void _emit(UserSettings next, {bool persist = true}) {
    next = _normalizeProModeAccess(next);
    if (_entitlementsManaged)
      next = _withBillingEntitlements(next, _paidEntitlements);
    if (next == _settings) return;
    _revision++;
    _settings = next;
    if (!_controller.isClosed) {
      _controller.add(_settings);
    }
    if (persist) {
      unawaited(
        _persist(_settings).catchError((Object error, StackTrace stack) {
          RuntimeDiagnosticsService.instance.record(
            error,
            stack,
            operation: "Save preferences",
          );
        }),
      );
    }
  }

  UserSettings _normalizeProModeAccess(UserSettings settings) {
    if (canUseProModePreview) return settings;

    final discovery = settings.matchDiscovery;
    final sanitizedDiscovery = discovery.businessOnly
        ? discovery.copyWith(businessOnly: false)
        : discovery;

    if (settings.uxMode == AppUxMode.party &&
        identical(sanitizedDiscovery, discovery)) {
      return settings;
    }

    return settings.copyWith(
      uxMode: AppUxMode.party,
      matchDiscovery: sanitizedDiscovery,
    );
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

  void setListenRole(ListenMatchRole role) {
    final cur = _settings.matchDiscovery;
    if (cur.listenRole == role) return;
    _emit(_settings.copyWith(matchDiscovery: cur.copyWith(listenRole: role)));
  }

  void setTreasureRadiusMiles(double miles) {
    final safe = miles
        .clamp(
          MatchDiscoverySettings.minRadiusMiles,
          MatchDiscoverySettings.maxRadiusMiles,
        )
        .toDouble();
    final cur = _settings.matchDiscovery;
    if (cur.treasureRadiusMiles == safe) return;
    _emit(
      _settings.copyWith(
        matchDiscovery: cur.copyWith(treasureRadiusMiles: safe),
      ),
    );
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

  void recordActiveModePenalty({required Duration lockDuration}) {
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
    if (mode == AppUxMode.business && !canUseProModePreview) {
      mode = AppUxMode.party;
    }
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
    if (!enabled && _settings.demoModeEnabled) {
      _emit(_settings.copyWith(demoModeEnabled: false));
    }
  }

  void setDemoSimulatedNearbyLocationEnabled(bool enabled) {
    if (!enabled && _settings.demoSimulatedNearbyLocationEnabled) {
      _emit(_settings.copyWith(demoSimulatedNearbyLocationEnabled: false));
    }
  }

  void setDemoSimulatedNearbyOffsetMiles(double miles) {
    final safe = miles.clamp(0.0, 1.0).toDouble();
    if (_settings.demoSimulatedNearbyOffsetMiles == safe) return;
    _emit(_settings.copyWith(demoSimulatedNearbyOffsetMiles: safe));
  }

  void setDemoForceMatchAllWithinRadius(bool enabled) {
    if (!enabled && _settings.demoForceMatchAllWithinRadius) {
      _emit(_settings.copyWith(demoForceMatchAllWithinRadius: false));
    }
  }

  void setDemoFastPresenceRefreshEnabled(bool enabled) {
    if (!enabled && _settings.demoFastPresenceRefreshEnabled) {
      _emit(_settings.copyWith(demoFastPresenceRefreshEnabled: false));
    }
  }

  void setTextScaleFactor(double value) {
    final safe = value.clamp(0.9, 1.6).toDouble();
    if (_settings.textScaleFactor == safe) return;
    _emit(_settings.copyWith(textScaleFactor: safe));
  }

  void setMatchNotificationsEnabled(bool enabled) {
    if (_settings.matchNotificationsEnabled == enabled) return;
    _emit(_settings.copyWith(matchNotificationsEnabled: enabled));
  }

  void setMatchSoundEnabled(bool enabled) {
    if (_settings.matchSoundEnabled == enabled) return;
    _emit(_settings.copyWith(matchSoundEnabled: enabled));
  }

  void setRareMatchSoundEnabled(bool enabled) {
    if (_settings.rareMatchSoundEnabled == enabled) return;
    _emit(_settings.copyWith(rareMatchSoundEnabled: enabled));
  }

  void setMatchSoundVolume(double volume) {
    final safe = volume.clamp(0.0, 1.0).toDouble();
    if (_settings.matchSoundVolume == safe) return;
    _emit(_settings.copyWith(matchSoundVolume: safe));
  }

  void setSimpleModeEnabled(bool enabled) {
    if (_settings.simpleModeEnabled == enabled) return;
    _emit(_settings.copyWith(simpleModeEnabled: enabled));
  }

  void setAlwaysUseNormalMode(bool enabled) {
    if (_settings.alwaysUseNormalMode == enabled) return;
    _emit(_settings.copyWith(alwaysUseNormalMode: enabled));
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

  void setPartyUnlockHighlightPending(bool pending) {
    if (_settings.partyUnlockHighlightPending == pending) return;
    _emit(_settings.copyWith(partyUnlockHighlightPending: pending));
  }

  void unlockPartyFromSimpleMode() {
    _emit(
      _settings.copyWith(
        simpleModeEnabled: false,
        simpleModeCompleted: true,
        simpleModeStageIndex: 5,
        partyUnlockHighlightPending: true,
      ),
    );
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
