import "dart:async";
import "dart:math";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/geoquery_service.dart";
import "package:prox/services/keyword_quality_service.dart";
import "package:prox/services/user_profile_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/utils/bounded_async_map.dart";

class MatchingRuntimeService {
  MatchingRuntimeService._({
    String? Function()? uidProvider,
    Future<UserProfile?> Function(String)? profileLoader,
  }) : _uidProvider =
           uidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _profileLoader =
           profileLoader ??
           ((uid) => UserProfileService.instance.getProfileOnce(uid));

  @visibleForTesting
  factory MatchingRuntimeService.forTesting({
    required String? Function() uidProvider,
    required Future<UserProfile?> Function(String) profileLoader,
  }) => MatchingRuntimeService._(
    uidProvider: uidProvider,
    profileLoader: profileLoader,
  );

  static final MatchingRuntimeService instance = MatchingRuntimeService._();
  final String? Function() _uidProvider;
  final Future<UserProfile?> Function(String) _profileLoader;

  final UserSettingsService _settings = UserSettingsService.instance;
  static const Duration _profileFetchTimeout = Duration(seconds: 4);
  static const Duration _sharedKeywordsTimeout = Duration(seconds: 5);
  static const Duration _travelRecentMovementWindow = Duration(minutes: 30);
  static const int _maxTreasureCandidates = 24;

  List<String> _myKeywords = const <String>[];
  _MatchKeywordVectors _myVectors = const _MatchKeywordVectors.empty();
  DateTime? _myKeywordsAt;
  String? _keywordsUid;
  Future<void>? _myKeywordFetch;
  int _sessionRevision = 0;
  final Map<String, DateTime> _peerCacheAt = {};
  final Map<String, Future<List<String>>> _peerFetches = {};
  static const _cacheTtl = Duration(minutes: 2);
  static const _maxCachedPeers = 200;
  final Map<String, List<String>> _peerKeywordCache = <String, List<String>>{};
  final Map<String, _MatchKeywordVectors> _peerVectorCache =
      <String, _MatchKeywordVectors>{};

  void clearSession() {
    _sessionRevision++;
    _myKeywords = const [];
    _myVectors = const _MatchKeywordVectors.empty();
    _myKeywordsAt = null;
    _keywordsUid = null;
    _myKeywordFetch = null;
    _peerKeywordCache.clear();
    _peerVectorCache.clear();
    _peerCacheAt.clear();
    _peerFetches.clear();
  }

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
      return raw
          .where((d) {
            final ts = d.presenceTs;
            if (ts == null) return false;
            final bool recentlyMoving =
                !ts.isAfter(now.add(const Duration(minutes: 2))) &&
                now.difference(ts) <= _travelRecentMovementWindow;
            return recentlyMoving;
          })
          .toList(growable: false);
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
      return raw
          .where((d) {
            final peerMode = _peerModeKind(d);
            if (peerMode != MatchingModeKind.listen) return false;

            final peerRole = _peerListenRole(d);
            if (peerRole == null) return false;
            return peerRole != localRole;
          })
          .toList(growable: false);
    }

    if (settings.modeKind == MatchingModeKind.normal) {
      final revision = _synchronizeSession();
      await _refreshMyKeywordsIfNeeded();
      if (!_sessionIsCurrent(revision)) return const [];
      final candidates = raw.where(
        (doc) =>
            _peerModeKind(doc) == MatchingModeKind.normal &&
            normalModesCanMatch(
              local: settings.normalMode,
              peer: normalModeForPeer(doc),
            ),
      );
      final results = await boundedAsyncMap(candidates, (doc) async {
        if (!_sessionIsCurrent(revision)) return null;
        try {
          final matches = await _hasComplementaryIntentWithDoc(
            doc,
          ).timeout(_sharedKeywordsTimeout, onTimeout: () => false);
          return matches ? doc : null;
        } catch (_) {
          return null;
        }
      });
      if (!_sessionIsCurrent(revision)) return const [];
      final intentMatches = results.whereType<NearbyDoc>().toList(
        growable: false,
      );

      if (settings.normalMode == NormalMatchMode.passive &&
          effectiveRadiusMiles(settings) > 15.0) {
        final List<NearbyDoc> constrained = <NearbyDoc>[];
        for (final doc in intentMatches) {
          if (doc.distanceMiles <= 10.0) {
            constrained.add(doc);
            continue;
          }

          final shared = await sharedKeywordsWith(
            doc.uid,
          ).timeout(_sharedKeywordsTimeout, onTimeout: () => const <String>[]);
          if (!_sessionIsCurrent(revision)) return const [];
          if (shared.isNotEmpty) constrained.add(doc);
        }
        return prioritizeActivePeers(
          constrained,
          localNormalMode: settings.normalMode,
        );
      }

      if (settings.keywordMode != KeywordMatchMode.similar) {
        final effectiveKeywordMode = _effectiveKeywordModeForUnlocks(settings);
        final List<NearbyDoc> strict = <NearbyDoc>[];
        for (final doc in intentMatches) {
          final include = await _passesKeywordMode(
            otherUid: doc.uid,
            keywordMode: effectiveKeywordMode,
          ).timeout(_sharedKeywordsTimeout, onTimeout: () => false);
          if (!_sessionIsCurrent(revision)) return const [];
          if (include) strict.add(doc);
        }
        return prioritizeActivePeers(
          strict,
          localNormalMode: settings.normalMode,
        );
      }

      return prioritizeActivePeers(
        intentMatches,
        localNormalMode: settings.normalMode,
      );
    }

    return raw;
  }

  static List<NearbyDoc> prioritizeActivePeers(
    Iterable<NearbyDoc> docs, {
    required NormalMatchMode localNormalMode,
  }) {
    final ranked = docs.toList(growable: false);
    ranked.sort((a, b) {
      final aPeerActive = normalModeForPeer(a) == NormalMatchMode.active;
      final bPeerActive = normalModeForPeer(b) == NormalMatchMode.active;

      final aPriority =
          (localNormalMode == NormalMatchMode.active || aPeerActive) ? 0 : 1;
      final bPriority =
          (localNormalMode == NormalMatchMode.active || bPeerActive) ? 0 : 1;
      final byMode = aPriority.compareTo(bPriority);
      if (byMode != 0) return byMode;
      return a.distanceMiles.compareTo(b.distanceMiles);
    });
    return ranked;
  }

  static bool normalModesCanMatch({
    required NormalMatchMode local,
    required NormalMatchMode? peer,
  }) =>
      peer != null &&
      (local == NormalMatchMode.active || peer == NormalMatchMode.active);

  static NormalMatchMode? normalModeForPeer(NearbyDoc doc) {
    final modeName = _readPeerSettingStringFromData(
      doc.data,
      const <List<String>>[
        <String>["normalMode"],
        <String>["matching", "normalMode"],
        <String>["matchingSettings", "normalMode"],
        <String>["settings", "matching", "normalMode"],
        <String>["presence", "normalMode"],
      ],
    );
    switch (_normalizePeerTokenStatic(modeName)) {
      case "active":
        return NormalMatchMode.active;
      case "passive":
        return NormalMatchMode.passive;
      default:
        return null;
    }
  }

  static bool hasComplementaryIntent({
    required Iterable<String> mySearching,
    required Iterable<String> myProviding,
    required Iterable<String> theirSearching,
    required Iterable<String> theirProviding,
  }) {
    final mineSearching = _normalizedKeywordSet(mySearching);
    final mineProviding = _normalizedKeywordSet(myProviding);
    final theirsSearching = _normalizedKeywordSet(theirSearching);
    final theirsProviding = _normalizedKeywordSet(theirProviding);

    if (mineSearching.isEmpty ||
        mineProviding.isEmpty ||
        theirsSearching.isEmpty ||
        theirsProviding.isEmpty)
      return false;
    return mineSearching.intersection(theirsProviding).isNotEmpty ||
        mineProviding.intersection(theirsSearching).isNotEmpty;
  }

  static Set<String> _normalizedKeywordSet(Iterable<String> values) {
    return KeywordQualityService.sanitizeList(values.toList(growable: false))
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<bool> _hasComplementaryIntentWithDoc(NearbyDoc doc) async {
    final revision = _synchronizeSession();
    await _refreshMyKeywordsIfNeeded();
    if (!_sessionIsCurrent(revision)) return false;
    final peer = await _peerVectorsForDoc(doc);
    if (!_sessionIsCurrent(revision)) return false;
    return hasComplementaryIntent(
      mySearching: _myVectors.searching,
      myProviding: _myVectors.provide,
      theirSearching: peer.searching,
      theirProviding: peer.provide,
    );
  }

  Future<_MatchKeywordVectors> _peerVectorsForDoc(NearbyDoc doc) async {
    final fromDoc = _keywordVectorsFromUserDoc(doc.data);
    if (!fromDoc.isEmpty) return fromDoc;
    return _peerVectors(doc.uid);
  }

  _MatchKeywordVectors _keywordVectorsFromUserDoc(Map<String, dynamic> data) {
    try {
      if (data.isEmpty) {
        return const _MatchKeywordVectors.empty();
      }
      final profile = UserProfile.fromMap("candidate", data);
      return _keywordVectorsForProfile(profile);
    } catch (_) {
      return const _MatchKeywordVectors.empty();
    }
  }

  Future<List<TreasureTarget>> rankTreasureTargets(List<NearbyDoc> raw) async {
    final revision = _synchronizeSession();
    if (!_sessionIsCurrent(revision)) return const [];
    final candidates =
        (raw.toList()
              ..sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles)))
            .take(_maxTreasureCandidates);
    final results = await boundedAsyncMap(candidates, (d) async {
      if (!_sessionIsCurrent(revision)) return null;
      List<String> shared;
      try {
        shared = await sharedKeywordsWith(
          d.uid,
        ).timeout(_sharedKeywordsTimeout, onTimeout: () => const <String>[]);
      } catch (_) {
        return null;
      }
      if (shared.isEmpty) return null;
      return TreasureTarget(doc: d, sharedKeywords: shared);
    });
    if (!_sessionIsCurrent(revision)) return const [];
    final out = results.whereType<TreasureTarget>().toList();

    out.sort((a, b) {
      final byKeywords = b.sharedKeywords.length.compareTo(
        a.sharedKeywords.length,
      );
      if (byKeywords != 0) return byKeywords;
      return a.doc.distanceMiles.compareTo(b.doc.distanceMiles);
    });
    return out;
  }

  Future<List<String>> sharedKeywordsWith(String otherUid) async {
    final revision = _synchronizeSession();
    try {
      await _refreshMyKeywordsIfNeeded();
      if (!_sessionIsCurrent(revision)) return const [];
      final peer = await _peerKeywords(otherUid);
      if (!_sessionIsCurrent(revision)) return const [];
      if (_myKeywords.isEmpty || peer.isEmpty) return const <String>[];

      final mine = _myKeywords.toSet();
      final shared = peer.where(mine.contains).toSet().toList(growable: false)
        ..sort();
      return shared;
    } catch (_) {
      return const <String>[];
    }
  }

  int _synchronizeSession() {
    final uid = _uidProvider() ?? "";
    if (_keywordsUid != uid) {
      clearSession();
      _keywordsUid = uid;
    }
    return _sessionRevision;
  }

  bool _sessionIsCurrent(int revision) =>
      _synchronizeSession() == revision && (_keywordsUid?.isNotEmpty ?? false);

  Future<void> _refreshMyKeywordsIfNeeded() {
    _synchronizeSession();
    final uid = _keywordsUid ?? "";
    if (uid.isEmpty) {
      return Future<void>.value();
    }

    final now = DateTime.now();
    if (_myKeywordsAt != null && now.difference(_myKeywordsAt!) < _cacheTtl) {
      return Future<void>.value();
    }
    return _myKeywordFetch ??= _loadMyKeywords(uid, now);
  }

  Future<void> _loadMyKeywords(String uid, DateTime now) async {
    final revision = _sessionRevision;
    try {
      final p = await _profileLoader(uid).timeout(_profileFetchTimeout);
      if (!_sessionIsCurrent(revision)) return;
      _myVectors = _keywordVectorsForProfile(p);
      _myKeywords = _keywordsForProfile(p);
      _myKeywordsAt = now;
    } catch (_) {
      if (!_sessionIsCurrent(revision)) return;
      _myVectors = const _MatchKeywordVectors.empty();
      _myKeywords = const <String>[];
      _myKeywordsAt = null;
    } finally {
      if (revision == _sessionRevision) _myKeywordFetch = null;
    }
  }

  Future<List<String>> _peerKeywords(String uid) {
    final cached = _peerKeywordCache[uid];
    final at = _peerCacheAt[uid];
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheTtl) {
      return Future.value(cached);
    }
    return _peerFetches[uid] ??= _loadPeerKeywords(uid);
  }

  Future<List<String>> _loadPeerKeywords(String uid) async {
    final revision = _sessionRevision;
    try {
      final p = await _profileLoader(uid).timeout(_profileFetchTimeout);
      if (!_sessionIsCurrent(revision)) return const [];
      if (_peerCacheAt.length >= _maxCachedPeers &&
          !_peerCacheAt.containsKey(uid)) {
        final oldest = _peerCacheAt.keys.first;
        _peerCacheAt.remove(oldest);
        _peerVectorCache.remove(oldest);
        _peerKeywordCache.remove(oldest);
      }
      _peerVectorCache[uid] = _keywordVectorsForProfile(p);
      final kws = _keywordsForProfile(p);
      _peerKeywordCache[uid] = kws;
      _peerCacheAt.remove(uid);
      _peerCacheAt[uid] = DateTime.now();
      return kws;
    } catch (_) {
      if (!_sessionIsCurrent(revision)) return const [];
      // Empty/failed reads are transient during onboarding and profile saves.
      // Do not cache them, otherwise matching can become one-sided until the
      // process is restarted.
      _peerVectorCache.remove(uid);
      _peerKeywordCache.remove(uid);
      return const <String>[];
    } finally {
      if (revision == _sessionRevision) _peerFetches.remove(uid);
    }
  }

  KeywordMatchMode _effectiveKeywordModeForUnlocks(
    MatchDiscoverySettings settings,
  ) {
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

    final revision = _synchronizeSession();
    await _refreshMyKeywordsIfNeeded();
    if (!_sessionIsCurrent(revision)) return false;
    final peerKeywords = await _peerKeywords(otherUid);
    if (!_sessionIsCurrent(revision)) return false;
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
    if (!_sessionIsCurrent(revision)) return false;
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
    final revision = _synchronizeSession();
    await _peerKeywords(uid);
    if (!_sessionIsCurrent(revision)) return const _MatchKeywordVectors.empty();
    return _peerVectorCache[uid] ?? const _MatchKeywordVectors.empty();
  }

  _MatchKeywordVectors _keywordVectorsForProfile(UserProfile? p) {
    if (p == null) return const _MatchKeywordVectors.empty();
    final searching = KeywordQualityService.sanitizeList(
      p.searchingFor,
    ).cleaned.toList(growable: false)..sort();
    final provide = KeywordQualityService.sanitizeList(
      p.canProvide,
    ).cleaned.toList(growable: false)..sort();
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
    return _readPeerSettingStringFromData(doc.data, paths);
  }

  static String _readPeerSettingStringFromData(
    Map<String, dynamic> data,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      dynamic node = data;
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
    return _normalizePeerTokenStatic(raw);
  }

  static String _normalizePeerTokenStatic(String raw) {
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

  const _MatchKeywordVectors({required this.searching, required this.provide});

  const _MatchKeywordVectors.empty()
    : searching = const <String>[],
      provide = const <String>[];

  bool get isEmpty => searching.isEmpty || provide.isEmpty;
}
