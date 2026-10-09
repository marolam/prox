import 'package:prox/models/user_settings.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

/// Connections and public availability returned by the trusted server.
class MatchingAccessSnapshot {
  const MatchingAccessSnapshot({
    this.publicUnlocked = false,
    this.publicUnlockedAt,
    this.publicUnlockNotifiedAt,
    this.partyScope,
    this.checkedAt,
    this.latitude,
    this.longitude,
    this.directUids = const <String>{},
    this.treeMatches = const <String, TreeMatchConnection>{},
  });

  static const empty = MatchingAccessSnapshot();
  final bool publicUnlocked;
  final int? publicUnlockedAt;
  final int? publicUnlockNotifiedAt;
  final String? partyScope;
  final int? checkedAt;
  final double? latitude;
  final double? longitude;
  final Set<String> directUids;
  final Map<String, TreeMatchConnection> treeMatches;

  bool get publicUnlockNotificationPending =>
      publicUnlocked && publicUnlockNotifiedAt == null;

  factory MatchingAccessSnapshot.fromMap(Map<String, dynamic> data) {
    final graphInvalidated = data['graphInvalidated'] == true;
    final direct = graphInvalidated
        ? <String>{}
        : _strings(data['directUids']).toSet();
    final tree = <String, TreeMatchConnection>{};
    final entries = data['treeMatches'];
    if (!graphInvalidated && entries is List) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        final uid = (entry['uid'] as String?)?.trim() ?? '';
        final mutual = _strings(entry['mutualUids']);
        // A tree connection always needs a known direct mutual person.
        if (uid.isEmpty || direct.contains(uid) || !mutual.any(direct.contains))
          continue;
        tree[uid] = TreeMatchConnection(
          uid: uid,
          mutualUids: List.unmodifiable(mutual.where(direct.contains)),
          mutualNames: List.unmodifiable(_strings(entry['mutualNames'])),
        );
      }
    }
    return MatchingAccessSnapshot(
      publicUnlocked: data['publicUnlocked'] == true,
      publicUnlockedAt: (data['publicUnlockedAt'] as num?)?.toInt(),
      publicUnlockNotifiedAt: (data['publicUnlockNotifiedAt'] as num?)?.toInt(),
      partyScope: data['partyScope'] as String?,
      checkedAt: (data['checkedAt'] as num?)?.toInt(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      directUids: Set.unmodifiable(direct),
      treeMatches: Map.unmodifiable(tree),
    );
  }

  MatchingAccessSnapshot withPublicUnlocked(bool unlocked) =>
      MatchingAccessSnapshot(
        publicUnlocked: unlocked,
        publicUnlockedAt: publicUnlockedAt,
        publicUnlockNotifiedAt: publicUnlockNotifiedAt,
        partyScope: partyScope,
        checkedAt: checkedAt,
        latitude: latitude,
        longitude: longitude,
        directUids: directUids,
        treeMatches: treeMatches,
      );

  /// Public availability is a fresh decision for this physical area, not a
  /// lifetime entitlement. Party and Tree do not depend on location density.
  bool publicReceiptIsCurrent({
    required int nowMs,
    required double? localLatitude,
    required double? localLongitude,
    required int? locationAt,
  }) {
    const maxAge = 15 * 60 * 1000;
    bool recent(int? timestamp) =>
        timestamp != null &&
        nowMs - timestamp >= -60 * 1000 &&
        nowMs - timestamp <= maxAge;
    bool valid(double? value, double limit) =>
        value != null && value.isFinite && value.abs() <= limit;
    if (!publicUnlocked ||
        !recent(checkedAt) ||
        !recent(locationAt) ||
        !valid(latitude, 90) ||
        !valid(longitude, 180) ||
        !valid(localLatitude, 90) ||
        !valid(localLongitude, 180))
      return false;
    const radians = math.pi / 180;
    final lat = (latitude! - localLatitude!) * radians;
    final lon = (longitude! - localLongitude!) * radians;
    final h =
        math.pow(math.sin(lat / 2), 2) +
        math.cos(latitude! * radians) *
            math.cos(localLatitude * radians) *
            math.pow(math.sin(lon / 2), 2);
    final miles = 7917.6 * math.asin(math.sqrt(h.clamp(0, 1)));
    return miles <= .1;
  }

  /// Legacy public settings stay within Party + Tree until the server unlocks.
  MatchPartyScope effectiveScope(MatchPartyScope requested) {
    switch (requested) {
      case MatchPartyScope.partyOnly:
        return MatchPartyScope.partyOnly;
      case MatchPartyScope.tree:
      case MatchPartyScope.extendedOnly:
      case MatchPartyScope.none:
        return MatchPartyScope.tree;
      case MatchPartyScope.public:
      case MatchPartyScope.all:
        return publicUnlocked ? MatchPartyScope.public : MatchPartyScope.tree;
    }
  }

  bool allows(String uid, MatchPartyScope requested) {
    switch (effectiveScope(requested)) {
      case MatchPartyScope.partyOnly:
        return directUids.contains(uid);
      case MatchPartyScope.tree:
        return directUids.contains(uid) || treeMatches.containsKey(uid);
      case MatchPartyScope.public:
        return true;
      default:
        return false;
    }
  }

  /// Discovery requires both people to allow the connection. Peer settings are
  /// server-projected public profile fields, never a client-provided party ID.
  bool allowsPeer({
    required String uid,
    required MatchPartyScope requested,
    required Map<String, dynamic> peerProfile,
  }) {
    if (!allows(uid, requested)) return false;
    final matching = peerProfile['matching'];
    final rawScope =
        peerProfile['partyScope'] ??
        (matching is Map ? matching['partyScope'] : null);
    final peerPublic = peerProfile['publicMatchingUnlocked'] == true;
    final peerScope = switch (rawScope) {
      'partyOnly' => MatchPartyScope.partyOnly,
      'tree' || 'extendedOnly' => MatchPartyScope.tree,
      'public' || 'all' when peerPublic => MatchPartyScope.public,
      _ => MatchPartyScope.tree,
    };
    return switch (peerScope) {
      MatchPartyScope.partyOnly => directUids.contains(uid),
      MatchPartyScope.tree =>
        directUids.contains(uid) || treeMatches.containsKey(uid),
      MatchPartyScope.public => true,
      _ => false,
    };
  }

  static List<String> _strings(dynamic value) => value is List
      ? value
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(growable: false)
      : const [];

  @override
  bool operator ==(Object other) =>
      other is MatchingAccessSnapshot &&
      other.publicUnlocked == publicUnlocked &&
      other.publicUnlockedAt == publicUnlockedAt &&
      other.publicUnlockNotifiedAt == publicUnlockNotifiedAt &&
      other.partyScope == partyScope &&
      setEquals(other.directUids, directUids) &&
      mapEquals(other.treeMatches, treeMatches);

  @override
  int get hashCode => Object.hash(
    publicUnlocked,
    publicUnlockedAt,
    publicUnlockNotifiedAt,
    partyScope,
    Object.hashAllUnordered(directUids),
    Object.hashAllUnordered(treeMatches.values),
  );
}

class TreeMatchConnection {
  const TreeMatchConnection({
    required this.uid,
    required this.mutualUids,
    required this.mutualNames,
  });
  final String uid;
  final List<String> mutualUids;
  final List<String> mutualNames;

  String get label => mutualNames.isEmpty
      ? 'Tree match · You share a Party connection'
      : 'Tree match · You both know ${mutualNames.join(', ')}';

  @override
  bool operator ==(Object other) =>
      other is TreeMatchConnection &&
      other.uid == uid &&
      listEquals(other.mutualUids, mutualUids) &&
      listEquals(other.mutualNames, mutualNames);

  @override
  int get hashCode =>
      Object.hash(uid, Object.hashAll(mutualUids), Object.hashAll(mutualNames));
}
