import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:prox/models/matching_access.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/auth/authenticated_callable.dart';
import 'package:prox/services/user_settings_service.dart';
import 'package:prox/services/presence_writer.dart';

export 'package:prox/models/matching_access.dart';

/// Reads server-owned matching access, clearing graph data at account changes.
class MatchingAccessService extends ChangeNotifier {
  MatchingAccessService({
    Stream<String?> Function()? accountChanges,
    String? Function()? currentUid,
    Stream<Map<String, dynamic>?> Function(String uid)? watchReceipt,
    Future<Map<String, dynamic>> Function(String uid)? loadAccess,
    Future<void> Function(String uid)? acknowledgeUnlock,
    void Function(MatchingAccessSnapshot access, bool canonicalScope)?
    applyAccess,
    Map<String, dynamic> Function()? currentLocation,
    DateTime Function()? now,
  }) : _accounts =
           accountChanges ??
           (() => FirebaseAuth.instance.authStateChanges().map((u) => u?.uid)),
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _watchReceipt = watchReceipt ?? _firestoreReceipt,
       _loadAccess = loadAccess ?? _callAccess,
       _acknowledgeUnlock = acknowledgeUnlock ?? _callAcknowledge,
       _applyAccess = applyAccess ?? _applySettings,
       _currentLocation = currentLocation ?? _deviceLocation,
       _now = now ?? DateTime.now;

  static final instance = MatchingAccessService();
  final Stream<String?> Function() _accounts;
  final String? Function() _currentUid;
  final Stream<Map<String, dynamic>?> Function(String) _watchReceipt;
  final Future<Map<String, dynamic>> Function(String) _loadAccess;
  final Future<void> Function(String) _acknowledgeUnlock;
  final void Function(MatchingAccessSnapshot, bool) _applyAccess;
  final Map<String, dynamic> Function() _currentLocation;
  final DateTime Function() _now;
  StreamSubscription<String?>? _accountSubscription;
  StreamSubscription<Map<String, dynamic>?>? _receiptSubscription;
  MatchingAccessSnapshot _snapshot = MatchingAccessSnapshot.empty;
  MatchingAccessSnapshot _closedPublicSnapshot = MatchingAccessSnapshot.empty;
  MatchingAccessSnapshot _publishedSnapshot = MatchingAccessSnapshot.empty;
  String? _uid;
  int _revision = 0;
  DateTime? _refreshedAt;
  Future<MatchingAccessSnapshot>? _pending;
  Object? lastError;
  bool _started = false;
  int _graphRevision = 0;
  bool _refreshAgain = false;
  String? _pendingLocalScope;
  int _scopeRevision = 0;
  int? _acknowledgedAt;

  /// Protect a deliberate choice until the server confirms the same scope.
  /// In particular, a delayed public-unlock receipt must not undo Party Only.
  void recordLocalScopeSelection(MatchPartyScope scope) {
    start();
    _pendingLocalScope = switch (scope) {
      MatchPartyScope.partyOnly => 'partyOnly',
      MatchPartyScope.tree || MatchPartyScope.extendedOnly => 'tree',
      MatchPartyScope.none => 'tree',
      _ => 'public',
    };
    _scopeRevision++;
  }

  MatchingAccessSnapshot get current {
    if (_uid != _currentUid()) return MatchingAccessSnapshot.empty;
    return _snapshot.publicUnlocked && !_publicReceiptIsCurrent(_snapshot)
        ? _closedPublicSnapshot
        : _snapshot;
  }

  bool _publicReceiptIsCurrent(MatchingAccessSnapshot access) {
    final local = _currentLocation();
    final point = local['geopoint'];
    return access.publicReceiptIsCurrent(
      nowMs: _now().millisecondsSinceEpoch,
      localLatitude: point is GeoPoint
          ? point.latitude
          : (local['latitude'] as num?)?.toDouble(),
      localLongitude: point is GeoPoint
          ? point.longitude
          : (local['longitude'] as num?)?.toDouble(),
      locationAt: _millis(local['locationTs']),
    );
  }

  void start() {
    if (_started) return;
    _started = true;
    _accountSubscription = _accounts().distinct().listen(_bind);
    _bind(_currentUid());
  }

  void _bind(String? uid) {
    if (_uid == uid && _receiptSubscription != null) return;
    _revision++;
    _uid = uid;
    _snapshot = MatchingAccessSnapshot.empty;
    _closedPublicSnapshot = MatchingAccessSnapshot.empty;
    _publishedSnapshot = MatchingAccessSnapshot.empty;
    _refreshedAt = null;
    _pending = null;
    _graphRevision++;
    _refreshAgain = false;
    _pendingLocalScope = null;
    _scopeRevision++;
    _acknowledgedAt = null;
    lastError = null;
    unawaited(_receiptSubscription?.cancel());
    _receiptSubscription = null;
    notifyListeners();
    if (uid == null || uid.isEmpty) return;
    final revision = _revision;
    _receiptSubscription = _watchReceipt(uid).listen(
      (raw) {
        if (!_isCurrent(uid, revision)) return;
        if (raw?['graphInvalidated'] == true) {
          _graphRevision++;
          _refreshAgain = true;
          _publish({
            ...raw!,
            'directUids': <String>[],
            'treeMatches': <Map<String, dynamic>>[],
          }, canonicalScope: true);
          unawaited(refresh(force: true));
        } else {
          _publish(raw ?? <String, dynamic>{}, canonicalScope: true);
        }
      },
      onError: (Object error) {
        if (!_isCurrent(uid, revision)) return;
        _closeAccess(error);
      },
    );
    unawaited(refresh());
  }

  bool _isCurrent(String uid, int revision) =>
      _uid == uid && _currentUid() == uid && _revision == revision;

  void _publish(Map<String, dynamic> raw, {bool canonicalScope = false}) {
    final next = MatchingAccessSnapshot.fromMap({
      ...raw,
      'publicUnlockNotifiedAt':
          raw['publicUnlockNotifiedAt'] ?? _acknowledgedAt,
    });
    _acknowledgedAt = next.publicUnlockNotifiedAt;
    _snapshot = next;
    _closedPublicSnapshot = next.withPublicUnlocked(false);
    lastError = null;
    final scope = switch (_snapshot.partyScope) {
      'partyOnly' => 'partyOnly',
      'tree' || 'extendedOnly' || 'none' => 'tree',
      'public' || 'all' => 'public',
      _ => null,
    };
    if (canonicalScope && _pendingLocalScope != null) {
      if (scope == _pendingLocalScope) {
        _pendingLocalScope = null;
      } else {
        canonicalScope = false;
      }
    }
    _applyAccess(current, canonicalScope);
    _notifyPolicyIfChanged();
  }

  void _notifyPolicyIfChanged() {
    final next = current;
    if (next == _publishedSnapshot) return;
    _publishedSnapshot = next;
    _applyAccess(next, false);
    notifyListeners();
  }

  void _closeAccess(Object error) {
    lastError = error;
    _snapshot = MatchingAccessSnapshot(
      publicUnlockedAt: _snapshot.publicUnlockedAt,
      publicUnlockNotifiedAt: _snapshot.publicUnlockNotifiedAt,
      partyScope: _snapshot.partyScope,
    );
    _closedPublicSnapshot = _snapshot;
    _applyAccess(_snapshot, false);
    _publishedSnapshot = current;
    notifyListeners();
  }

  /// Called after nearby presence updates and on app resume. Repeated queries
  /// share one request and use a short throttle to avoid polling every rebuild.
  Future<MatchingAccessSnapshot> refresh({
    String? expectedUid,
    bool force = false,
  }) async {
    start();
    final uid = _currentUid();
    if (uid == null || (expectedUid != null && expectedUid != uid)) {
      return MatchingAccessSnapshot.empty;
    }
    if (_uid != uid) _bind(uid);
    _notifyPolicyIfChanged();
    if (_pending != null) return _pending!;
    if (!force &&
        _refreshedAt != null &&
        _now().difference(_refreshedAt!) < const Duration(seconds: 30)) {
      return current;
    }
    final revision = _revision;
    return _pending = _refresh(uid, revision);
  }

  Future<MatchingAccessSnapshot> _refresh(String uid, int revision) async {
    final graphRevision = _graphRevision;
    _refreshAgain = false;
    final scopeRevision = _scopeRevision;
    try {
      final raw = await _loadAccess(uid).timeout(const Duration(seconds: 20));
      if (!_isCurrent(uid, revision)) return MatchingAccessSnapshot.empty;
      if (graphRevision != _graphRevision) return current;
      if (raw['graphInvalidated'] == true) _refreshAgain = true;
      _refreshedAt = _now();
      _publish(raw, canonicalScope: scopeRevision == _scopeRevision);
      return current;
    } catch (error) {
      if (!_isCurrent(uid, revision)) return MatchingAccessSnapshot.empty;
      // Density belongs to the current area. A failed refresh cannot keep
      // public discovery open on the strength of an older area's receipt.
      _closeAccess(error);
      return current;
    } finally {
      if (_isCurrent(uid, revision)) {
        _pending = null;
        if (_refreshAgain) unawaited(refresh(force: true));
      }
    }
  }

  Future<void> acknowledgePublicUnlock() async {
    final uid = _currentUid();
    final revision = _revision;
    if (uid == null || !current.publicUnlockNotificationPending) return;
    await _acknowledgeUnlock(uid);
    if (!_isCurrent(uid, revision)) return;
    _acknowledgedAt = _now().millisecondsSinceEpoch;
    _publish({
      'publicUnlocked': _snapshot.publicUnlocked,
      'publicUnlockedAt': _snapshot.publicUnlockedAt,
      'publicUnlockNotifiedAt': _acknowledgedAt,
      'partyScope': _snapshot.partyScope,
      'checkedAt': _snapshot.checkedAt,
      'latitude': _snapshot.latitude,
      'longitude': _snapshot.longitude,
      'directUids': _snapshot.directUids.toList(),
      'treeMatches': _snapshot.treeMatches.values
          .map(
            (entry) => {
              'uid': entry.uid,
              'mutualUids': entry.mutualUids,
              'mutualNames': entry.mutualNames,
            },
          )
          .toList(),
    });
  }

  static Stream<Map<String, dynamic>?> _firestoreReceipt(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('matchingAccess')
          .doc('current')
          .snapshots(includeMetadataChanges: true)
          .where(
            (doc) =>
                !doc.metadata.isFromCache && !doc.metadata.hasPendingWrites,
          )
          .map((doc) {
            final data = doc.data();
            if (data == null) return null;
            return data.map(
              (key, value) => MapEntry(
                key,
                value is Timestamp ? value.millisecondsSinceEpoch : value,
              ),
            );
          });

  static Future<Map<String, dynamic>> _callAccess(String uid) async {
    final result = await callAuthenticatedFunction<dynamic>(
      'getMatchingAccess',
      {'expectedUid': uid},
    );
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<void> _callAcknowledge(String uid) async {
    await callAuthenticatedFunction<dynamic>(
      'acknowledgePublicMatchingUnlock',
      {'expectedUid': uid},
    );
  }

  static void _applySettings(MatchingAccessSnapshot access, bool canonical) =>
      UserSettingsService.instance.applyMatchingAccess(
        publicUnlocked: access.publicUnlocked,
        publicUnlockedAt: access.publicUnlockedAt,
        partyScope: canonical ? access.partyScope : null,
      );

  static Map<String, dynamic> _deviceLocation() =>
      PresenceWriter.instance.travelSample;

  static int? _millis(dynamic value) => switch (value) {
    Timestamp timestamp => timestamp.millisecondsSinceEpoch,
    DateTime date => date.millisecondsSinceEpoch,
    num number => number.toInt(),
    _ => null,
  };

  @override
  void dispose() {
    _revision++;
    unawaited(_accountSubscription?.cancel());
    unawaited(_receiptSubscription?.cancel());
    super.dispose();
  }
}
