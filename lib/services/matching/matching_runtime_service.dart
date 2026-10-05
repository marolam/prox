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
import "package:prox/services/presence_writer.dart";
import "package:prox/services/matching/travel_match_policy.dart";
import "package:geolocator/geolocator.dart";
import "package:cloud_firestore/cloud_firestore.dart";

class MatchingRuntimeService {
  MatchingRuntimeService._({
    Map<String, dynamic> Function()? travelSampleProvider,
    String? Function()? uidProvider,
    Future<UserProfile?> Function(String)? profileLoader,
  }) : _travelSampleProvider =
           travelSampleProvider ?? (() => PresenceWriter.instance.travelSample),
       _uidProvider =
           uidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _profileLoader =
           profileLoader ??
           ((uid) => UserProfileService.instance.getProfileOnce(uid));

  @visibleForTesting
  factory MatchingRuntimeService.forTesting({
    Map<String, dynamic> Function()? travelSampleProvider,
    required String? Function() uidProvider,
    required Future<UserProfile?> Function(String) profileLoader,
  }) => MatchingRuntimeService._(
    travelSampleProvider: travelSampleProvider,
    uidProvider: uidProvider,
    profileLoader: profileLoader,
  );

  static final MatchingRuntimeService instance = MatchingRuntimeService._();
  final Map<String, dynamic> Function() _travelSampleProvider;
  final String? Function() _uidProvider;
  final Future<UserProfile?> Function(String) _profileLoader;

  final UserSettingsService _settings = UserSettingsService.instance;
  static const Duration _profileFetchTimeout = Duration(seconds: 4);
  static const Duration _sharedKeywordsTimeout = Duration(seconds: 5);
  static const int _maxTreasureCandidates = 50;

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
      final revision = _synchronizeSession();
      await _refreshMyKeywordsIfNeeded();
      if (!_sessionIsCurrent(revision)) return const [];
      final now = DateTime.now();
      final local = _travelSampleProvider();
      final candidates = raw.where((doc) {
        final presence = doc.data['presence'];
        return _peerModeKind(doc) == MatchingModeKind.travel &&
            presence is Map<String, dynamic> &&
            TravelMatchPolicy.canMatch(
              local: local,
              peer: presence,
              distanceMiles: local['geopoint'] is GeoPoint
                  ? Geolocator.distanceBetween(
                          (local['geopoint'] as GeoPoint).latitude,
                          (local['geopoint'] as GeoPoint).longitude,
                          doc.loc.latitude,
                          doc.loc.longitude,
                        ) /
                        1609.344
                  : doc.distanceMiles,
              radiusMiles: effectiveRadiusMiles(settings),
              now: now,
            );
      });
      final matches = await boundedAsyncMap(
        candidates,
        (doc) async =>
            await _passesCriteria(
              doc,
              settings,
            ).timeout(_sharedKeywordsTimeout, onTimeout: () => false)
            ? doc
            : null,
      );
      if (!_sessionIsCurrent(revision)) return const [];
      return matches.whereType<NearbyDoc>().toList(growable: false);
    }

    // Treasure produces area clues only after deliberate compass activation.
    if (settings.modeKind == MatchingModeKind.treasureHunt) return const [];

    if (settings.modeKind == MatchingModeKind.listen) {
      return raw
          .where((doc) => _peerModeKind(doc) == MatchingModeKind.listen)
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
          final matches = await _passesCriteria(
            doc,
            settings,
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
        <String>["presence", "normalMode"],
        <String>["normalMode"],
        <String>["matching", "normalMode"],
        <String>["matchingSettings", "normalMode"],
        <String>["settings", "matching", "normalMode"],
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

  Future<bool> _passesCriteria(
    NearbyDoc doc,
    MatchDiscoverySettings settings,
  ) async {
    if (!await _hasComplementaryIntentWithDoc(doc)) return false;
    final peer = await _peerVectorsForDoc(doc);
    final mineSearch = _normalizedKeywordSet(_myVectors.searching);
    final mineProvide = _normalizedKeywordSet(_myVectors.provide);
    final peerSearch = _normalizedKeywordSet(peer.searching);
    final peerProvide = _normalizedKeywordSet(peer.provide);
    final forward = mineSearch.intersection(peerProvide);
    final reverse = mineProvide.intersection(peerSearch);
    switch (_effectiveKeywordModeForUnlocks(settings)) {
      case KeywordMatchMode.reciprocalOpposite:
        return forward.isNotEmpty && reverse.isNotEmpty;
      case KeywordMatchMode.keywordChain:
        return {
              ...mineSearch,
              ...mineProvide,
            }.intersection({...peerSearch, ...peerProvide}).length >=
            2;
      default:
        return forward.isNotEmpty || reverse.isNotEmpty;
    }
  }

  Future<List<TreasureTarget>> rankTreasureTargets(
    List<NearbyDoc> raw, {
    MatchDiscoverySettings? settings,
  }) async {
    final discovery = settings ?? _settings.current.matchDiscovery;
    final revision = _synchronizeSession();
    await _refreshMyKeywordsIfNeeded();
    if (!_sessionIsCurrent(revision)) return const [];
    final candidates =
        (raw
                .where(
                  (doc) =>
                      _peerModeKind(doc) == MatchingModeKind.normal ||
                      _peerModeKind(doc) == MatchingModeKind.treasureHunt,
                )
                .toList()
              ..sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles)))
            .take(_maxTreasureCandidates);
    final results = await boundedAsyncMap(candidates, (doc) async {
      try {
        if (!await _passesCriteria(
          doc,
          discovery,
        ).timeout(_sharedKeywordsTimeout, onTimeout: () => false))
          return null;
        final peer = await _peerVectorsForDoc(doc);
        final shared = <String>{
          ..._normalizedKeywordSet(
            _myVectors.searching,
          ).intersection(_normalizedKeywordSet(peer.provide)),
          ..._normalizedKeywordSet(
            _myVectors.provide,
          ).intersection(_normalizedKeywordSet(peer.searching)),
        }.toList()..sort();
        return TreasureTarget(doc: doc, sharedKeywords: shared);
      } catch (_) {
        return null;
      }
    });
    if (!_sessionIsCurrent(revision)) return const [];
    return results.whereType<TreasureTarget>().toList(growable: false);
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
      <String>["presence", "modeKind"],
      <String>["modeKind"],
      <String>["matching", "modeKind"],
      <String>["matchingSettings", "modeKind"],
      <String>["settings", "matching", "modeKind"],
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

  bool get isEmpty => searching.isEmpty && provide.isEmpty;
}
