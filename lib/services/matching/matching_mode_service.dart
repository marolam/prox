import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/matching/active_mode_policy_service.dart";
import "package:prox/services/user_settings_service.dart";

enum ProxMatchingMode { passive, active }

/// MatchingModeService
///
class MatchingModeService extends ChangeNotifier {
  MatchingModeService._();
  static final MatchingModeService instance = MatchingModeService._();

  final UserSettingsService _settings = UserSettingsService.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  ProxMatchingMode get mode {
    _settings.clearActiveLockIfExpired();
    ActiveModePolicyService.instance.ensureWatching();
    final s = _settings.current.matchDiscovery;
    final backendLocked = ActiveModePolicyService.instance.isLockedByBackend;
    final active = s.modeKind == MatchingModeKind.normal &&
        s.normalMode == NormalMatchMode.active &&
        !s.isActiveLocked &&
        !backendLocked;
    return active ? ProxMatchingMode.active : ProxMatchingMode.passive;
  }

  bool get isActive => mode == ProxMatchingMode.active;

  MatchDiscoverySettings get discovery => _settings.current.matchDiscovery;

  MatchingModeKind get modeKind => discovery.modeKind;

  NormalMatchMode get normalMode => discovery.normalMode;

  bool get isActiveLocked => discovery.isActiveLocked || ActiveModePolicyService.instance.isLockedByBackend;

  void setMode(ProxMatchingMode next) {
    _settings.clearActiveLockIfExpired();
    final desired =
        (next == ProxMatchingMode.active) ? NormalMatchMode.active : NormalMatchMode.passive;
    _settings.setMatchingMode(MatchingModeKind.normal);
    _settings.setNormalMatchMode(desired);
    _syncModeToServer();
    notifyListeners();
  }

  void setModeKind(MatchingModeKind next) {
    _settings.setMatchingMode(next);
    _syncModeToServer();
    notifyListeners();
  }

  void setTreasureRadiusMiles(double miles) {
    _settings.setTreasureRadiusMiles(miles);
    _syncModeToServer();
    notifyListeners();
  }

  void setRadiusMiles(double miles) {
    _settings.setRadiusMiles(miles);
    _syncModeToServer();
    notifyListeners();
  }

  void registerActiveNoResponsePenalty() {
    _settings.recordActiveModePenalty(lockDuration: const Duration(minutes: 10));
    notifyListeners();
  }

  void toggle() {
    setMode(isActive ? ProxMatchingMode.passive : ProxMatchingMode.active);
  }

  void _syncModeToServer() {
    final uid = _auth.currentUser?.uid ?? "";
    if (uid.isEmpty) return;

    final d = _settings.current.matchDiscovery;
    unawaited(
      _fs
          .collection("users")
          .doc(uid)
          .collection("settings")
          .doc("matching")
          .set(
        <String, Object?>{
          "modeKind": d.modeKind.name,
          "normalMode": d.normalMode.name,
          "radiusMiles": d.radiusMiles,
          "treasureRadiusMiles": d.treasureRadiusMiles,
          "updatedAtClientMs": DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ),
    );
  }
}
