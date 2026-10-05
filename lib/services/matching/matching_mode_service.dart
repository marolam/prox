import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/services/matching/active_mode_policy_service.dart";
import "package:prox/services/user_settings_service.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/services/runtime_diagnostics_service.dart";

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
    final active =
        s.modeKind == MatchingModeKind.normal &&
        s.normalMode == NormalMatchMode.active &&
        !s.isActiveLocked &&
        !backendLocked;
    return active ? ProxMatchingMode.active : ProxMatchingMode.passive;
  }

  bool get isActive => mode == ProxMatchingMode.active;

  MatchDiscoverySettings get discovery => _settings.current.matchDiscovery;

  MatchingModeKind get modeKind => discovery.modeKind;

  NormalMatchMode get normalMode => discovery.normalMode;

  ListenMatchRole get listenRole => discovery.listenRole;

  bool get isActiveLocked =>
      discovery.isActiveLocked ||
      ActiveModePolicyService.instance.isLockedByBackend;

  void setMode(ProxMatchingMode next) {
    _settings.clearActiveLockIfExpired();
    final desired = (next == ProxMatchingMode.active)
        ? NormalMatchMode.active
        : NormalMatchMode.passive;
    _settings.setMatchingMode(MatchingModeKind.normal);
    _settings.setNormalMatchMode(desired);
    _syncModeToServer();
    notifyListeners();
  }

  void setModeKind(MatchingModeKind next) {
    final current = _settings.current.matchDiscovery;
    _settings.updateMatchDiscovery(
      current.copyWith(
        modeKind: next,
        normalMode: current.modeKind == next
            ? current.normalMode
            : NormalMatchMode.passive,
      ),
    );
    _syncModeToServer();
    if (next == MatchingModeKind.listen && current.modeKind != next) {
      // Announce a fresh observation now rather than waiting for the next
      // stationary pulse. The writer still enforces foreground and permissions.
      unawaited(_announceListenPresence());
    }
    notifyListeners();
  }

  Future<void> _announceListenPresence() async {
    try {
      await PresenceWriter.instance.writeOneShot(reason: 'listen_mode_enter');
    } catch (error, stack) {
      RuntimeDiagnosticsService.instance.record(
        error,
        stack,
        operation: 'Announce Listen availability',
      );
    }
  }

  void setListenRole(ListenMatchRole next) {
    _settings.setListenRole(next);
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
    _settings.recordActiveModePenalty(
      lockDuration: const Duration(minutes: 10),
    );
    _syncModeToServer();
    notifyListeners();
  }

  void toggle() {
    setMode(isActive ? ProxMatchingMode.passive : ProxMatchingMode.active);
  }

  Future<void> _syncQueue = Future<void>.value();
  int _syncRevision = 0;

  void syncSessionToServer() => _syncModeToServer();

  void _syncModeToServer() {
    final uid = _auth.currentUser?.uid ?? "";
    if (uid.isEmpty) return;

    final d = _settings.current.matchDiscovery;
    final revision = ++_syncRevision;
    _syncQueue = _syncQueue
        .catchError((Object _) {})
        .then((_) async {
          if (revision != _syncRevision || _auth.currentUser?.uid != uid)
            return;
          final batch = _fs.batch();
          batch.set(_fs.doc("users/$uid/settings/matching"), <String, Object?>{
            "modeKind": d.modeKind.name,
            "normalMode": d.normalMode.name,
            "listenRole": d.listenRole.name,
            "radiusMiles": d.radiusMiles,
            "businessOnly": d.businessOnly,
            "immediateOnly": d.immediateOnly,
            "ageBracket": d.ageBracket.name,
            "partyScope": d.partyScope.name,
            "keywordMode": d.keywordMode.name,
            "treasureRadiusMiles": d.treasureRadiusMiles,
            "updatedAtClientMs": DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true));
          batch.set(_fs.doc("users/$uid/presence/current"), <String, Object?>{
            "modeKind": d.modeKind.name,
            "normalMode": d.normalMode.name,
            "listenRole": d.listenRole.name,
            "matchingUpdatedAtClientMs": DateTime.now().millisecondsSinceEpoch,
          }, SetOptions(merge: true));
          await batch.commit();
        })
        .catchError((Object error, StackTrace stack) {
          RuntimeDiagnosticsService.instance.record(
            error,
            stack,
            operation: "Synchronize matching mode",
          );
        });
  }
}
