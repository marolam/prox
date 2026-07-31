import "package:flutter/foundation.dart";

enum MatchPartyScope {
  none,
  partyOnly,
  tree,
  public,

  // legacy / compatibility
  all,
  extendedOnly,
}

enum AppUxMode {
  party,
  business,
}

enum MatchingModeKind {
  off,
  normal,
  listen,
  treasureHunt,
  travel,
}

enum NormalMatchMode {
  passive,
  active,
}

enum ListenMatchRole {
  speak,
  listen,
}

enum KeywordMatchMode {
  similar,
  strict,
  singleKeyword,
  reciprocalOpposite,
  keywordChain,
}

class MatchDiscoverySettings {
  final double radiusMiles;
  final bool highRadiusUnlocked;
  final bool businessOnly;
  final bool immediateOnly;
  final MatchingModeKind modeKind;
  final NormalMatchMode normalMode;
  final ListenMatchRole listenRole;
  final double treasureRadiusMiles;
  final int activeLockUntilEpochMs;
  final int activePenaltyCount;
  final KeywordMatchMode keywordMode;
  final bool singleKeywordMatchUnlocked;
  final bool reciprocalMatchUnlocked;
  final bool keywordChainUnlocked;

  final MatchPartyScope partyScope;
  final int? partyDepth;
  final int? precisionIndex;

  const MatchDiscoverySettings({
    required this.radiusMiles,
    this.highRadiusUnlocked = false,
    required this.businessOnly,
    required this.immediateOnly,
    this.modeKind = MatchingModeKind.normal,
    this.normalMode = NormalMatchMode.passive,
    this.listenRole = ListenMatchRole.speak,
    this.treasureRadiusMiles = 1.0,
    this.activeLockUntilEpochMs = 0,
    this.activePenaltyCount = 0,
    this.keywordMode = KeywordMatchMode.similar,
    this.singleKeywordMatchUnlocked = false,
    this.reciprocalMatchUnlocked = false,
    this.keywordChainUnlocked = false,
    MatchPartyScope partyScope = MatchPartyScope.public,
    this.partyDepth,
    this.precisionIndex,
  }) : partyScope = partyScope;

  static const double minRadiusMiles = 0.5;
  static const double maxRadiusMiles = 10.0;
  static const double extendedMaxRadiusMiles = 30.0;

  static double allowedMaxRadiusMiles({
    required bool highRadiusUnlocked,
    required bool businessOnly,
    required MatchingModeKind modeKind,
    required NormalMatchMode normalMode,
  }) {
    if (!businessOnly) return maxRadiusMiles;

    if (modeKind == MatchingModeKind.normal) {
      if (normalMode == NormalMatchMode.passive) {
        return highRadiusUnlocked ? extendedMaxRadiusMiles : 15.0;
      }
      return 15.0;
    }

    if (modeKind == MatchingModeKind.travel) {
      return 12.0;
    }

    return maxRadiusMiles;
  }

  const MatchDiscoverySettings.defaults()
      : radiusMiles = 2.0,
        highRadiusUnlocked = false,
        businessOnly = false,
        immediateOnly = false,
        modeKind = MatchingModeKind.normal,
        normalMode = NormalMatchMode.passive,
        listenRole = ListenMatchRole.speak,
        treasureRadiusMiles = 1.0,
        activeLockUntilEpochMs = 0,
        activePenaltyCount = 0,
        keywordMode = KeywordMatchMode.similar,
        singleKeywordMatchUnlocked = false,
        reciprocalMatchUnlocked = false,
        keywordChainUnlocked = false,
        partyScope = MatchPartyScope.public,
        partyDepth = 1,
        precisionIndex = 1;

  MatchDiscoverySettings copyWith({
    double? radiusMiles,
    bool? highRadiusUnlocked,
    bool? businessOnly,
    bool? immediateOnly,
    MatchingModeKind? modeKind,
    NormalMatchMode? normalMode,
    ListenMatchRole? listenRole,
    double? treasureRadiusMiles,
    int? activeLockUntilEpochMs,
    int? activePenaltyCount,
    KeywordMatchMode? keywordMode,
    bool? singleKeywordMatchUnlocked,
    bool? reciprocalMatchUnlocked,
    bool? keywordChainUnlocked,
    MatchPartyScope? partyScope,
    int? partyDepth,
    int? precisionIndex,
  }) {
    return MatchDiscoverySettings(
      radiusMiles: radiusMiles ?? this.radiusMiles,
      highRadiusUnlocked: highRadiusUnlocked ?? this.highRadiusUnlocked,
      businessOnly: businessOnly ?? this.businessOnly,
      immediateOnly: immediateOnly ?? this.immediateOnly,
      modeKind: modeKind ?? this.modeKind,
      normalMode: normalMode ?? this.normalMode,
      listenRole: listenRole ?? this.listenRole,
      treasureRadiusMiles: treasureRadiusMiles ?? this.treasureRadiusMiles,
      activeLockUntilEpochMs:
          activeLockUntilEpochMs ?? this.activeLockUntilEpochMs,
      activePenaltyCount: activePenaltyCount ?? this.activePenaltyCount,
      keywordMode: keywordMode ?? this.keywordMode,
      singleKeywordMatchUnlocked:
          singleKeywordMatchUnlocked ?? this.singleKeywordMatchUnlocked,
      reciprocalMatchUnlocked:
          reciprocalMatchUnlocked ?? this.reciprocalMatchUnlocked,
      keywordChainUnlocked: keywordChainUnlocked ?? this.keywordChainUnlocked,
      partyScope: partyScope ?? this.partyScope,
      partyDepth: partyDepth ?? this.partyDepth,
      precisionIndex: precisionIndex ?? this.precisionIndex,
    );
  }

  bool get matchingEnabled => modeKind != MatchingModeKind.off;

  bool get isActiveLocked {
    if (activeLockUntilEpochMs <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch < activeLockUntilEpochMs;
  }

  bool get isNormalActive =>
      modeKind == MatchingModeKind.normal &&
      normalMode == NormalMatchMode.active &&
      !isActiveLocked;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "radiusMiles": radiusMiles,
      "highRadiusUnlocked": highRadiusUnlocked,
      "businessOnly": businessOnly,
      "immediateOnly": immediateOnly,
      "modeKind": modeKind.name,
      "normalMode": normalMode.name,
      "listenRole": listenRole.name,
      "treasureRadiusMiles": treasureRadiusMiles,
      "activeLockUntilEpochMs": activeLockUntilEpochMs,
      "activePenaltyCount": activePenaltyCount,
      "keywordMode": keywordMode.name,
      "singleKeywordMatchUnlocked": singleKeywordMatchUnlocked,
      "reciprocalMatchUnlocked": reciprocalMatchUnlocked,
      "keywordChainUnlocked": keywordChainUnlocked,
      "partyScope": partyScope.name,
      "partyDepth": partyDepth,
      "precisionIndex": precisionIndex,
    };
  }

  static MatchDiscoverySettings fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const MatchDiscoverySettings.defaults();
    }

    final double radiusRaw = (raw["radiusMiles"] as num?)?.toDouble() ?? 2.0;
    final bool highRadiusUnlocked =
        (raw["highRadiusUnlocked"] as bool?) ?? false;
    final bool businessOnly = (raw["businessOnly"] as bool?) ?? false;
    final bool immediateOnly = (raw["immediateOnly"] as bool?) ?? false;
    final String modeName = (raw["modeKind"] as String?) ?? "normal";
    final String normalName = (raw["normalMode"] as String?) ?? "passive";
    final String listenRoleName = (raw["listenRole"] as String?) ?? "speak";
    final String keywordModeName = (raw["keywordMode"] as String?) ?? "similar";

    final MatchingModeKind modeKind = _matchingModeFromName(modeName);
    final NormalMatchMode normalMode = _normalModeFromName(normalName);
    final ListenMatchRole listenRole = _listenRoleFromName(listenRoleName);
    final double maxAllowed = allowedMaxRadiusMiles(
      highRadiusUnlocked: highRadiusUnlocked,
      businessOnly: businessOnly,
      modeKind: modeKind,
      normalMode: normalMode,
    );
    final double radius = radiusRaw.clamp(minRadiusMiles, maxAllowed);

    final double treasureRadiusRaw =
        (raw["treasureRadiusMiles"] as num?)?.toDouble() ?? 1.0;
    final double treasureRadius =
        treasureRadiusRaw.clamp(minRadiusMiles, maxRadiusMiles);

    final int activeLockUntilEpochMs =
        (raw["activeLockUntilEpochMs"] as num?)?.toInt() ?? 0;
    final int activePenaltyCount =
        (raw["activePenaltyCount"] as num?)?.toInt() ?? 0;
    final KeywordMatchMode keywordMode = _keywordModeFromName(keywordModeName);
    final bool singleKeywordMatchUnlocked =
        (raw["singleKeywordMatchUnlocked"] as bool?) ?? false;
    final bool reciprocalMatchUnlocked =
        (raw["reciprocalMatchUnlocked"] as bool?) ?? false;
    final bool keywordChainUnlocked =
        (raw["keywordChainUnlocked"] as bool?) ?? false;

    final String scopeName = (raw["partyScope"] as String?) ?? "public";
    final MatchPartyScope scope = _scopeFromName(scopeName);

    final int? depth = (raw["partyDepth"] as num?)?.toInt();
    final int? precision = (raw["precisionIndex"] as num?)?.toInt();

    return MatchDiscoverySettings(
      radiusMiles: radius,
      highRadiusUnlocked: highRadiusUnlocked,
      businessOnly: businessOnly,
      immediateOnly: immediateOnly,
      modeKind: modeKind,
      normalMode: normalMode,
      listenRole: listenRole,
      treasureRadiusMiles: treasureRadius,
      activeLockUntilEpochMs: activeLockUntilEpochMs,
      activePenaltyCount: activePenaltyCount,
      keywordMode: keywordMode,
      singleKeywordMatchUnlocked: singleKeywordMatchUnlocked,
      reciprocalMatchUnlocked: reciprocalMatchUnlocked,
      keywordChainUnlocked: keywordChainUnlocked,
      partyScope: scope,
      partyDepth: depth ?? 1,
      precisionIndex: precision ?? 1,
    );
  }

  static MatchingModeKind _matchingModeFromName(String name) {
    switch (name) {
      case "off":
        return MatchingModeKind.off;
      case "treasureHunt":
        return MatchingModeKind.treasureHunt;
      case "travel":
        return MatchingModeKind.travel;
      case "listen":
        return MatchingModeKind.listen;
      case "normal":
      default:
        return MatchingModeKind.normal;
    }
  }

  static NormalMatchMode _normalModeFromName(String name) {
    switch (name) {
      case "active":
        return NormalMatchMode.active;
      case "passive":
      default:
        return NormalMatchMode.passive;
    }
  }

  static ListenMatchRole _listenRoleFromName(String name) {
    switch (name) {
      case "listen":
        return ListenMatchRole.listen;
      case "speak":
      default:
        return ListenMatchRole.speak;
    }
  }

  static MatchPartyScope _scopeFromName(String name) {
    switch (name) {
      case "none":
        return MatchPartyScope.none;
      case "partyOnly":
        return MatchPartyScope.partyOnly;
      case "tree":
        return MatchPartyScope.tree;
      case "public":
        return MatchPartyScope.public;

      case "all":
        return MatchPartyScope.public;
      case "extendedOnly":
        return MatchPartyScope.tree;

      default:
        return MatchPartyScope.public;
    }
  }

  static KeywordMatchMode _keywordModeFromName(String name) {
    switch (name) {
      case "strict":
        return KeywordMatchMode.strict;
      case "singleKeyword":
        return KeywordMatchMode.singleKeyword;
      case "reciprocalOpposite":
        return KeywordMatchMode.reciprocalOpposite;
      case "keywordChain":
        return KeywordMatchMode.keywordChain;
      case "similar":
      default:
        return KeywordMatchMode.similar;
    }
  }

  @override
  String toString() {
    return "MatchDiscoverySettings("
        "radiusMiles=$radiusMiles, "
        "highRadiusUnlocked=$highRadiusUnlocked, "
        "businessOnly=$businessOnly, "
        "immediateOnly=$immediateOnly, "
        "modeKind=$modeKind, "
        "normalMode=$normalMode, "
        "listenRole=$listenRole, "
        "treasureRadiusMiles=$treasureRadiusMiles, "
        "activeLockUntilEpochMs=$activeLockUntilEpochMs, "
        "activePenaltyCount=$activePenaltyCount, "
        "keywordMode=$keywordMode, "
        "partyScope=$partyScope, "
        "partyDepth=$partyDepth, "
        "precisionIndex=$precisionIndex"
        ")";
  }

  @override
  bool operator ==(Object other) {
    return other is MatchDiscoverySettings &&
        other.radiusMiles == radiusMiles &&
        other.highRadiusUnlocked == highRadiusUnlocked &&
        other.businessOnly == businessOnly &&
        other.immediateOnly == immediateOnly &&
        other.modeKind == modeKind &&
        other.normalMode == normalMode &&
        other.listenRole == listenRole &&
        other.treasureRadiusMiles == treasureRadiusMiles &&
        other.activeLockUntilEpochMs == activeLockUntilEpochMs &&
        other.activePenaltyCount == activePenaltyCount &&
        other.keywordMode == keywordMode &&
        other.singleKeywordMatchUnlocked == singleKeywordMatchUnlocked &&
        other.reciprocalMatchUnlocked == reciprocalMatchUnlocked &&
        other.keywordChainUnlocked == keywordChainUnlocked &&
        other.partyScope == partyScope &&
        other.partyDepth == partyDepth &&
        other.precisionIndex == precisionIndex;
  }

  @override
  int get hashCode => Object.hash(
        radiusMiles,
        highRadiusUnlocked,
        businessOnly,
        immediateOnly,
        modeKind,
        normalMode,
        listenRole,
        treasureRadiusMiles,
        activeLockUntilEpochMs,
        activePenaltyCount,
        keywordMode,
        singleKeywordMatchUnlocked,
        reciprocalMatchUnlocked,
        keywordChainUnlocked,
        partyScope,
        partyDepth,
        precisionIndex,
      );
}

class UserSettings {
  final AppUxMode uxMode;
  final bool hasSeenModeExplainer;

  final String partyCosmeticPackId;
  final String businessCosmeticPackId;

  final bool trustPulseEnabled;
  final bool referralSignalEnabled;
  final bool demoModeEnabled;
  final bool demoSimulatedNearbyLocationEnabled;
  final double demoSimulatedNearbyOffsetMiles;
  final bool demoForceMatchAllWithinRadius;
  final bool demoFastPresenceRefreshEnabled;
  final double textScaleFactor;
  final bool matchNotificationsEnabled;
  final bool matchSoundEnabled;
  final bool rareMatchSoundEnabled;

  final MatchDiscoverySettings matchDiscovery;
  final bool hasSeenBusinessIntro;
  final bool hasSeenBusinessFilterHint;
  final bool hasSeenBusinessReactivate;

  final bool businessAvatarEnabled;
  final String? businessAvatarNote;

  final Map<String, bool> seenBusinessPrompts;

  final bool hasSeenTreePublicEligibleNudge;
  final bool simpleModeEnabled;
  final bool simpleModeCompleted;
  final int simpleModeStageIndex;

  const UserSettings({
    required this.uxMode,
    required this.hasSeenModeExplainer,
    required this.partyCosmeticPackId,
    required this.businessCosmeticPackId,
    required this.trustPulseEnabled,
    required this.referralSignalEnabled,
    required this.demoModeEnabled,
    required this.demoSimulatedNearbyLocationEnabled,
    required this.demoSimulatedNearbyOffsetMiles,
    required this.demoForceMatchAllWithinRadius,
    required this.demoFastPresenceRefreshEnabled,
    required this.textScaleFactor,
    required this.matchNotificationsEnabled,
    required this.matchSoundEnabled,
    required this.rareMatchSoundEnabled,
    required this.matchDiscovery,
    required this.hasSeenBusinessIntro,
    required this.hasSeenBusinessFilterHint,
    required this.hasSeenBusinessReactivate,
    required this.businessAvatarEnabled,
    this.businessAvatarNote,
    required this.seenBusinessPrompts,
    required this.hasSeenTreePublicEligibleNudge,
    required this.simpleModeEnabled,
    required this.simpleModeCompleted,
    required this.simpleModeStageIndex,
  });

  const UserSettings.defaults()
      : uxMode = AppUxMode.party,
        hasSeenModeExplainer = false,
        partyCosmeticPackId = "default",
        businessCosmeticPackId = "default",
        trustPulseEnabled = true,
        referralSignalEnabled = true,
        demoModeEnabled = false,
        demoSimulatedNearbyLocationEnabled = false,
        demoSimulatedNearbyOffsetMiles = 0.25,
        demoForceMatchAllWithinRadius = false,
        demoFastPresenceRefreshEnabled = false,
        textScaleFactor = 1.0,
        matchNotificationsEnabled = true,
        matchSoundEnabled = true,
        rareMatchSoundEnabled = true,
        matchDiscovery = const MatchDiscoverySettings.defaults(),
        hasSeenBusinessIntro = false,
        hasSeenBusinessFilterHint = false,
        hasSeenBusinessReactivate = false,
        businessAvatarEnabled = false,
        businessAvatarNote = null,
        seenBusinessPrompts = const <String, bool>{},
        hasSeenTreePublicEligibleNudge = false,
        simpleModeEnabled = true,
        simpleModeCompleted = false,
        simpleModeStageIndex = 0;

  UserSettings copyWith({
    AppUxMode? uxMode,
    bool? hasSeenModeExplainer,
    String? partyCosmeticPackId,
    String? businessCosmeticPackId,
    bool? trustPulseEnabled,
    bool? referralSignalEnabled,
    bool? demoModeEnabled,
    bool? demoSimulatedNearbyLocationEnabled,
    double? demoSimulatedNearbyOffsetMiles,
    bool? demoForceMatchAllWithinRadius,
    bool? demoFastPresenceRefreshEnabled,
    double? textScaleFactor,
    bool? matchNotificationsEnabled,
    bool? matchSoundEnabled,
    bool? rareMatchSoundEnabled,
    MatchDiscoverySettings? matchDiscovery,
    bool? hasSeenBusinessIntro,
    bool? hasSeenBusinessFilterHint,
    bool? hasSeenBusinessReactivate,
    bool? businessAvatarEnabled,
    String? businessAvatarNote,
    Map<String, bool>? seenBusinessPrompts,
    bool? hasSeenTreePublicEligibleNudge,
    bool? simpleModeEnabled,
    bool? simpleModeCompleted,
    int? simpleModeStageIndex,
  }) {
    return UserSettings(
      uxMode: uxMode ?? this.uxMode,
      hasSeenModeExplainer: hasSeenModeExplainer ?? this.hasSeenModeExplainer,
      partyCosmeticPackId: partyCosmeticPackId ?? this.partyCosmeticPackId,
      businessCosmeticPackId:
          businessCosmeticPackId ?? this.businessCosmeticPackId,
      trustPulseEnabled: trustPulseEnabled ?? this.trustPulseEnabled,
      referralSignalEnabled:
          referralSignalEnabled ?? this.referralSignalEnabled,
      demoModeEnabled: demoModeEnabled ?? this.demoModeEnabled,
      demoSimulatedNearbyLocationEnabled: demoSimulatedNearbyLocationEnabled ??
          this.demoSimulatedNearbyLocationEnabled,
      demoSimulatedNearbyOffsetMiles:
          demoSimulatedNearbyOffsetMiles ?? this.demoSimulatedNearbyOffsetMiles,
      demoForceMatchAllWithinRadius:
          demoForceMatchAllWithinRadius ?? this.demoForceMatchAllWithinRadius,
      demoFastPresenceRefreshEnabled:
          demoFastPresenceRefreshEnabled ?? this.demoFastPresenceRefreshEnabled,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
        matchNotificationsEnabled:
          matchNotificationsEnabled ?? this.matchNotificationsEnabled,
        matchSoundEnabled: matchSoundEnabled ?? this.matchSoundEnabled,
        rareMatchSoundEnabled:
          rareMatchSoundEnabled ?? this.rareMatchSoundEnabled,
      matchDiscovery: matchDiscovery ?? this.matchDiscovery,
      hasSeenBusinessIntro: hasSeenBusinessIntro ?? this.hasSeenBusinessIntro,
      hasSeenBusinessFilterHint:
          hasSeenBusinessFilterHint ?? this.hasSeenBusinessFilterHint,
      hasSeenBusinessReactivate:
          hasSeenBusinessReactivate ?? this.hasSeenBusinessReactivate,
      businessAvatarEnabled:
          businessAvatarEnabled ?? this.businessAvatarEnabled,
      businessAvatarNote: businessAvatarNote ?? this.businessAvatarNote,
      seenBusinessPrompts: seenBusinessPrompts ?? this.seenBusinessPrompts,
      hasSeenTreePublicEligibleNudge:
          hasSeenTreePublicEligibleNudge ?? this.hasSeenTreePublicEligibleNudge,
      simpleModeEnabled: simpleModeEnabled ?? this.simpleModeEnabled,
      simpleModeCompleted: simpleModeCompleted ?? this.simpleModeCompleted,
      simpleModeStageIndex: simpleModeStageIndex ?? this.simpleModeStageIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "uxMode": uxMode.name,
      "hasSeenModeExplainer": hasSeenModeExplainer,
      "partyCosmeticPackId": partyCosmeticPackId,
      "businessCosmeticPackId": businessCosmeticPackId,
      "trustPulseEnabled": trustPulseEnabled,
      "referralSignalEnabled": referralSignalEnabled,
      "demoModeEnabled": demoModeEnabled,
      "demoSimulatedNearbyLocationEnabled": demoSimulatedNearbyLocationEnabled,
      "demoSimulatedNearbyOffsetMiles": demoSimulatedNearbyOffsetMiles,
      "demoForceMatchAllWithinRadius": demoForceMatchAllWithinRadius,
      "demoFastPresenceRefreshEnabled": demoFastPresenceRefreshEnabled,
      "textScaleFactor": textScaleFactor,
      "matchNotificationsEnabled": matchNotificationsEnabled,
      "matchSoundEnabled": matchSoundEnabled,
      "rareMatchSoundEnabled": rareMatchSoundEnabled,
      "matchDiscovery": matchDiscovery.toJson(),
      "hasSeenBusinessIntro": hasSeenBusinessIntro,
      "hasSeenBusinessFilterHint": hasSeenBusinessFilterHint,
      "hasSeenBusinessReactivate": hasSeenBusinessReactivate,
      "businessAvatarEnabled": businessAvatarEnabled,
      "businessAvatarNote": businessAvatarNote,
      "seenBusinessPrompts": seenBusinessPrompts,
      "hasSeenTreePublicEligibleNudge": hasSeenTreePublicEligibleNudge,
      "simpleModeEnabled": simpleModeEnabled,
      "simpleModeCompleted": simpleModeCompleted,
      "simpleModeStageIndex": simpleModeStageIndex,
    };
  }

  static UserSettings fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const UserSettings.defaults();
    }

    final String uxRaw = (raw["uxMode"] as String?) ?? "party";
    final AppUxMode uxMode = _uxModeFromName(uxRaw);

    final bool seenModeExplainer =
        (raw["hasSeenModeExplainer"] as bool?) ?? false;

    final String partyPack =
        (raw["partyCosmeticPackId"] as String?)?.trim().isNotEmpty == true
            ? (raw["partyCosmeticPackId"] as String).trim()
            : "default";
    final String businessPack =
        (raw["businessCosmeticPackId"] as String?)?.trim().isNotEmpty == true
            ? (raw["businessCosmeticPackId"] as String).trim()
            : "default";

    final bool trustPulseEnabled = (raw["trustPulseEnabled"] as bool?) ?? true;
    final bool referralSignalEnabled =
        (raw["referralSignalEnabled"] as bool?) ?? true;
    const bool demoModeEnabled = false;
    const bool demoSimulatedNearbyLocationEnabled = false;
    const double demoSimulatedNearbyOffsetMiles = 0.25;
    const bool demoForceMatchAllWithinRadius = false;
    const bool demoFastPresenceRefreshEnabled = false;
    final double textScaleFactor =
        ((raw["textScaleFactor"] as num?)?.toDouble() ?? 1.0).clamp(0.9, 1.6);
    final bool matchNotificationsEnabled =
      (raw["matchNotificationsEnabled"] as bool?) ?? true;
    final bool matchSoundEnabled = (raw["matchSoundEnabled"] as bool?) ?? true;
    final bool rareMatchSoundEnabled =
      (raw["rareMatchSoundEnabled"] as bool?) ?? true;

    final mdRaw = raw["matchDiscovery"];
    final matchDiscovery = MatchDiscoverySettings.fromJson(mdRaw);

    final bool hasIntro = (raw["hasSeenBusinessIntro"] as bool?) ?? false;
    final bool hasFilterHint =
        (raw["hasSeenBusinessFilterHint"] as bool?) ?? false;
    final bool hasReactivate =
        (raw["hasSeenBusinessReactivate"] as bool?) ?? false;

    final bool avatarEnabled = (raw["businessAvatarEnabled"] as bool?) ?? false;
    final String? avatarNote = raw["businessAvatarNote"] as String?;

    final dynamic mapRaw = raw["seenBusinessPrompts"];
    Map<String, bool> prompts;
    if (mapRaw is Map) {
      prompts = mapRaw.map(
        (key, value) => MapEntry(key.toString(), value == true),
      );
    } else {
      prompts = <String, bool>{};
    }

    final bool seenTreeNudge =
        (raw["hasSeenTreePublicEligibleNudge"] as bool?) ?? false;
    final bool simpleModeEnabled = (raw["simpleModeEnabled"] as bool?) ?? true;
    final bool simpleModeCompleted =
        (raw["simpleModeCompleted"] as bool?) ?? false;
    final int simpleModeStageIndex =
        (raw["simpleModeStageIndex"] as num?)?.toInt() ?? 0;

    return UserSettings(
      uxMode: uxMode,
      hasSeenModeExplainer: seenModeExplainer,
      partyCosmeticPackId: partyPack,
      businessCosmeticPackId: businessPack,
      trustPulseEnabled: trustPulseEnabled,
      referralSignalEnabled: referralSignalEnabled,
      demoModeEnabled: demoModeEnabled,
      demoSimulatedNearbyLocationEnabled: demoSimulatedNearbyLocationEnabled,
      demoSimulatedNearbyOffsetMiles: demoSimulatedNearbyOffsetMiles,
      demoForceMatchAllWithinRadius: demoForceMatchAllWithinRadius,
      demoFastPresenceRefreshEnabled: demoFastPresenceRefreshEnabled,
      textScaleFactor: textScaleFactor,
      matchNotificationsEnabled: matchNotificationsEnabled,
      matchSoundEnabled: matchSoundEnabled,
      rareMatchSoundEnabled: rareMatchSoundEnabled,
      matchDiscovery: matchDiscovery,
      hasSeenBusinessIntro: hasIntro,
      hasSeenBusinessFilterHint: hasFilterHint,
      hasSeenBusinessReactivate: hasReactivate,
      businessAvatarEnabled: avatarEnabled,
      businessAvatarNote: avatarNote,
      seenBusinessPrompts: prompts,
      hasSeenTreePublicEligibleNudge: seenTreeNudge,
      simpleModeEnabled: simpleModeEnabled,
      simpleModeCompleted: simpleModeCompleted,
      simpleModeStageIndex: simpleModeStageIndex,
    );
  }

  static AppUxMode _uxModeFromName(String name) {
    switch (name) {
      case "business":
        return AppUxMode.business;
      case "party":
      default:
        return AppUxMode.party;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is UserSettings &&
        other.uxMode == uxMode &&
        other.hasSeenModeExplainer == hasSeenModeExplainer &&
        other.partyCosmeticPackId == partyCosmeticPackId &&
        other.businessCosmeticPackId == businessCosmeticPackId &&
        other.trustPulseEnabled == trustPulseEnabled &&
        other.referralSignalEnabled == referralSignalEnabled &&
        other.demoModeEnabled == demoModeEnabled &&
        other.demoSimulatedNearbyLocationEnabled ==
            demoSimulatedNearbyLocationEnabled &&
        other.demoSimulatedNearbyOffsetMiles ==
            demoSimulatedNearbyOffsetMiles &&
        other.demoForceMatchAllWithinRadius == demoForceMatchAllWithinRadius &&
        other.demoFastPresenceRefreshEnabled ==
            demoFastPresenceRefreshEnabled &&
        other.textScaleFactor == textScaleFactor &&
        other.matchNotificationsEnabled == matchNotificationsEnabled &&
        other.matchSoundEnabled == matchSoundEnabled &&
        other.rareMatchSoundEnabled == rareMatchSoundEnabled &&
        other.matchDiscovery == matchDiscovery &&
        other.hasSeenBusinessIntro == hasSeenBusinessIntro &&
        other.hasSeenBusinessFilterHint == hasSeenBusinessFilterHint &&
        other.hasSeenBusinessReactivate == hasSeenBusinessReactivate &&
        other.businessAvatarEnabled == businessAvatarEnabled &&
        other.businessAvatarNote == businessAvatarNote &&
        mapEquals(other.seenBusinessPrompts, seenBusinessPrompts) &&
        other.hasSeenTreePublicEligibleNudge ==
            hasSeenTreePublicEligibleNudge &&
        other.simpleModeEnabled == simpleModeEnabled &&
        other.simpleModeCompleted == simpleModeCompleted &&
        other.simpleModeStageIndex == simpleModeStageIndex;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        uxMode,
        hasSeenModeExplainer,
        partyCosmeticPackId,
        businessCosmeticPackId,
        trustPulseEnabled,
        referralSignalEnabled,
        demoModeEnabled,
        demoSimulatedNearbyLocationEnabled,
        demoSimulatedNearbyOffsetMiles,
        demoForceMatchAllWithinRadius,
        demoFastPresenceRefreshEnabled,
        textScaleFactor,
        matchNotificationsEnabled,
        matchSoundEnabled,
        rareMatchSoundEnabled,
        matchDiscovery,
        hasSeenBusinessIntro,
        hasSeenBusinessFilterHint,
        hasSeenBusinessReactivate,
        businessAvatarEnabled,
        businessAvatarNote,
        Object.hashAll(seenBusinessPrompts.entries
            .map((e) => Object.hash(e.key, e.value))),
        hasSeenTreePublicEligibleNudge,
        simpleModeEnabled,
        simpleModeCompleted,
        simpleModeStageIndex,
      ]);
}
