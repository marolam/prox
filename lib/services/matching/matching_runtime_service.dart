import "dart:async";
import "dart:math";

import "package:firebase_auth/firebase_auth.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/services/keyword_quality_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/user_settings_service.dart";

class MatchingRuntimeService {
  MatchingRuntimeService._();
  static final MatchingRuntimeService instance = MatchingRuntimeService._();

  final UserSettingsService _settings = UserSettingsService.instance;
  static const Duration _profileFetchTimeout = Duration(seconds: 4);
  static const Duration _sharedKeywordsTimeout = Duration(seconds: 5);
  static const Duration _travelRecentMovementWindow = Duration(minutes: 30);
  static const int _maxTreasureCandidates = 24;

  List<String> _myKeywords = const <String>[];
  _MatchKeywordVectors _myVectors = const _MatchKeywordVectors.empty();
  DateTime? _myKeywordsAt;
  final Map<String, List<String>> _peerKeywordCache = <String, List<String>>{};
  final Map<String, _MatchKeywordVectors> _peerVectorCache =
      <String, _MatchKeywordVectors>{};

  double effectiveRadiusMiles(MatchDiscoverySettings s) {
    if (s.modeKind == MatchingModeKind.off) return 0;

    final maxAllowed = MatchDiscoverySettings.allowedMaxRadiusMiles(
      highRadiusUnlocked: s.highRadiusUnlocked,
      businessOnly: s.businessOnly,
      modeKind: s.modeKind,
      normalMode: s.normalMode,
    );

    if (s.modeKind == MatchingModeKind.treasureHunt) {
      return s.treasureRadiusMiles;
    }
    if (s.modeKind == MatchingModeKind.travel) {
      return min(maxAllowed, max(2.5, s.radiusMiles * 2));
    }
    return min(maxAllowed, s.radiusMiles);
  }

  Future<List<NearbyDoc>> filterByMode(List<NearbyDoc> raw) async {
    final settings = _settings.current.matchDiscovery;
    return filterByModeForSettings(raw, settings);
  }

  Future<List<NearbyDoc>> filterByModeForSettings(
    List<NearbyDoc> raw,
    MatchDiscoverySettings settings,
  ) async {
    if (settings.modeKind == MatchingModeKind.off) {
      return const <NearbyDoc>[];
    }

    if (settings.modeKind == MatchingModeKind.travel) {
      final now = DateTime.now();
      return raw.where((d) {
        final ts = d.presenceTs;
        if (ts == null) return false;
        final bool recentlyMoving =
            now.difference(ts) <= _travelRecentMovementWindow;
        return recentlyMoving;
      }).toList(growable: false);
    }

    if (settings.modeKind == MatchingModeKind.treasureHunt) {
      try {
        final hits = await rankTreasureTargets(raw);
        return hits.map((e) => e.doc).toList(growable: false);
      } catch (_) {
        return const <NearbyDoc>[];
      }
    }

    if (settings.modeKind == MatchingModeKind.listen) {
      final ListenMatchRole localRole = settings.listenRole;
      return raw.where((d) {
        final peerMode = _peerModeKind(d);
        if (peerMode != MatchingModeKind.listen) return false;

        final peerRole = _peerListenRole(d);
        if (peerRole == null) return false;
        return peerRole != localRole;
      }).toList(growable: false);
    }

    if (settings.modeKind == MatchingModeKind.normal &&
        settings.normalMode == NormalMatchMode.passive &&
        effectiveRadiusMiles(settings) > 15.0) {
      final List<NearbyDoc> constrained = <NearbyDoc>[];
      for (final doc in raw) {
        if (doc.distanceMiles <= 10.0) {
          constrained.add(doc);
          continue;
        }

        final shared = await sharedKeywordsWith(doc.uid)
            .timeout(_sharedKeywordsTimeout, onTimeout: () => const <String>[]);
        if (shared.isNotEmpty) {
          constrained.add(doc);
        }
      }
      return constrained;
    }

    if (settings.modeKind == MatchingModeKind.normal &&
        settings.keywordMode != KeywordMatchMode.similar) {
      final effectiveKeywordMode = _effectiveKeywordModeForUnlocks(settings);
      final List<NearbyDoc> strict = <NearbyDoc>[];
      for (final doc in raw) {
        final include = await _passesKeywordMode(
          otherUid: doc.uid,
          keywordMode: effectiveKeywordMode,
        ).timeout(_sharedKeywordsTimeout, onTimeout: () => false);
        if (include) {
          strict.add(doc);
        }
      }
      return strict;
    }

    return raw;
  }

  Future<List<TreasureTarget>> rankTreasureTargets(List<NearbyDoc> raw) async {
    final out = <TreasureTarget>[];
    final candidates = raw.take(_maxTreasureCandidates);
    for (final d in candidates) {
      List<String> shared;
      try {
        shared = await sharedKeywordsWith(d.uid)
            .timeout(_sharedKeywordsTimeout, onTimeout: () => const <String>[]);
      } catch (_) {
        continue;
      }
      if (shared.isEmpty) continue;
      out.add(TreasureTarget(doc: d, sharedKeywords: shared));
    }

    out.sort((a, b) {
      final byKeywords =
          b.sharedKeywords.length.compareTo(a.sharedKeywords.length);
      if (byKeywords != 0) return byKeywords;
      return a.doc.distanceMiles.compareTo(b.doc.distanceMiles);
    });
    return out;
  }

  Future<List<String>> sharedKeywordsWith(String otherUid) async {
    try {
      if (_myKeywords.isEmpty) {
        await _refreshMyKeywordsIfNeeded();
      }
      final peer = await _peerKeywords(otherUid);
      if (_myKeywords.isEmpty || peer.isEmpty) return const <String>[];

      final mine = _myKeywords.toSet();
      final shared = peer.where(mine.contains).toSet().toList(growable: false)
        ..sort();
      return shared;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _refreshMyKeywordsIfNeeded() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) {
      _myKeywords = const <String>[];
      return;
    }

    final now = DateTime.now();
    if (_myKeywordsAt != null &&
        now.difference(_myKeywordsAt!) < const Duration(minutes: 2)) {
      return;
    }

    try {
      final p = await UserProfileService.instance
          .getProfileOnce(uid)
          .timeout(_profileFetchTimeout);
      _myVectors = _keywordVectorsForProfile(p);
      _myKeywords = _keywordsForProfile(p);
      _myKeywordsAt = now;
    } catch (_) {
      _myVectors = const _MatchKeywordVectors.empty();
      _myKeywords = const <String>[];
      _myKeywordsAt = now;
    }
  }

  Future<List<String>> _peerKeywords(String uid) async {
    final cached = _peerKeywordCache[uid];
    if (cached != null) return cached;

    try {
      final p = await UserProfileService.instance
          .getProfileOnce(uid)
          .timeout(_profileFetchTimeout);
      _peerVectorCache[uid] = _keywordVectorsForProfile(p);
      final kws = _keywordsForProfile(p);
      _peerKeywordCache[uid] = kws;
      return kws;
    } catch (_) {
      _peerVectorCache[uid] = const _MatchKeywordVectors.empty();
      const kws = <String>[];
      _peerKeywordCache[uid] = kws;
      return kws;
    }
  }

  KeywordMatchMode _effectiveKeywordModeForUnlocks(
      MatchDiscoverySettings settings) {
    switch (settings.keywordMode) {
      case KeywordMatchMode.singleKeyword:
        return settings.singleKeywordMatchUnlocked
            ? KeywordMatchMode.singleKeyword
            : KeywordMatchMode.similar;
      case KeywordMatchMode.reciprocalOpposite:
        return settings.reciprocalMatchUnlocked
            ? KeywordMatchMode.reciprocalOpposite
            : KeywordMatchMode.similar;
      case KeywordMatchMode.keywordChain:
        return settings.keywordChainUnlocked
            ? KeywordMatchMode.keywordChain
            : KeywordMatchMode.similar;
      case KeywordMatchMode.strict:
      case KeywordMatchMode.similar:
        return settings.keywordMode;
    }
  }

  Future<bool> _passesKeywordMode({
    required String otherUid,
    required KeywordMatchMode keywordMode,
  }) async {
    if (keywordMode == KeywordMatchMode.similar) return true;

    if (_myKeywords.isEmpty) {
      await _refreshMyKeywordsIfNeeded();
    }
    final peerKeywords = await _peerKeywords(otherUid);
    if (_myKeywords.isEmpty || peerKeywords.isEmpty) return false;

    final mineSet = _myKeywords.toSet();
    final sharedCount = peerKeywords.where(mineSet.contains).toSet().length;

    if (keywordMode == KeywordMatchMode.strict ||
        keywordMode == KeywordMatchMode.singleKeyword) {
      return sharedCount >= 1;
    }

    if (keywordMode == KeywordMatchMode.keywordChain) {
      return sharedCount >= 2;
    }

    final mineVectors = _myVectors;
    final peerVectors = await _peerVectors(otherUid);
    if (mineVectors.isEmpty || peerVectors.isEmpty) return false;

    final searchToProvide = mineVectors.searching
        .where(peerVectors.provide.contains)
        .toSet()
        .isNotEmpty;
    final provideToSearch = mineVectors.provide
        .where(peerVectors.searching.contains)
        .toSet()
        .isNotEmpty;
    return searchToProvide && provideToSearch;
  }

  Future<_MatchKeywordVectors> _peerVectors(String uid) async {
    final cached = _peerVectorCache[uid];
    if (cached != null) return cached;
    await _peerKeywords(uid);
    return _peerVectorCache[uid] ?? const _MatchKeywordVectors.empty();
  }

  _MatchKeywordVectors _keywordVectorsForProfile(UserProfile? p) {
    if (p == null) return const _MatchKeywordVectors.empty();
    final searching = KeywordQualityService.sanitizeList(p.searchingFor)
        .cleaned
        .toList(growable: false)
      ..sort();
    final provide = KeywordQualityService.sanitizeList(p.canProvide)
        .cleaned
        .toList(growable: false)
      ..sort();
    return _MatchKeywordVectors(searching: searching, provide: provide);
  }

  List<String> _keywordsForProfile(UserProfile? p) {
    if (p == null) return const <String>[];

    final items = <String>{
      ...p.searchingFor,
      ...p.canProvide,
      if ((p.searching ?? "").trim().isNotEmpty) p.searching!.trim(),
      if ((p.providing ?? "").trim().isNotEmpty) p.providing!.trim(),
    };

    final out = <String>[];
    for (final item in items) {
      final normalized = item.toLowerCase().trim();
      if (normalized.isEmpty) continue;
      out.add(normalized);
      for (final token in normalized.split(RegExp(r"[^a-z0-9]+"))) {
        final t = token.trim();
        if (t.length >= 3) out.add(t);
      }
    }

    final sanitized = KeywordQualityService.sanitizeList(out);
    return sanitized.cleaned..sort();
  }

  MatchingModeKind _peerModeKind(NearbyDoc doc) {
    final String modeName = _readPeerSettingString(doc, const <List<String>>[
      <String>["modeKind"],
      <String>["matching", "modeKind"],
      <String>["matchingSettings", "modeKind"],
      <String>["settings", "matching", "modeKind"],
      <String>["presence", "modeKind"],
    ]);

    final normalized = _normalizePeerToken(modeName);
    switch (normalized) {
      case "off":
        return MatchingModeKind.off;
      case "treasurehunt":
        return MatchingModeKind.treasureHunt;
      case "travel":
        return MatchingModeKind.travel;
      case "listen":
      case "listenmode":
        return MatchingModeKind.listen;
      case "normal":
      default:
        return MatchingModeKind.normal;
    }
  }

  ListenMatchRole? _peerListenRole(NearbyDoc doc) {
    final String roleName = _readPeerSettingString(doc, const <List<String>>[
      <String>["listenRole"],
      <String>["matching", "listenRole"],
      <String>["matchingSettings", "listenRole"],
      <String>["settings", "matching", "listenRole"],
      <String>["presence", "listenRole"],
    ]);
    final normalized = _normalizePeerToken(roleName);
    switch (normalized) {
      case "speak":
        return ListenMatchRole.speak;
      case "listen":
        return ListenMatchRole.listen;
      default:
        return null;
    }
  }

  String _readPeerSettingString(NearbyDoc doc, List<List<String>> paths) {
    for (final path in paths) {
      dynamic node = doc.data;
      for (final segment in path) {
        if (node is! Map) {
          node = null;
          break;
        }
        node = node[segment];
      }
      if (node is String) {
        final value = node.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return "";
  }

  String _normalizePeerToken(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "");
  }
}

class TreasureTarget {
  final NearbyDoc doc;
  final List<String> sharedKeywords;

  const TreasureTarget({required this.doc, required this.sharedKeywords});
}

class _MatchKeywordVectors {
  final List<String> searching;
  final List<String> provide;

  const _MatchKeywordVectors({
    required this.searching,
    required this.provide,
  });

  const _MatchKeywordVectors.empty()
      : searching = const <String>[],
        provide = const <String>[];

  bool get isEmpty => searching.isEmpty || provide.isEmpty;
}
