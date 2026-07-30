import "package:firebase_remote_config/firebase_remote_config.dart";
import "package:flutter/foundation.dart";

import "package:prox/release/release_flags.dart";

class RolloutGateService {
  RolloutGateService._();
  static final RolloutGateService instance = RolloutGateService._();

  static const String _businessModeKillSwitchKey = "feature_kill_business_mode";

  bool _initialized = false;
  bool _remoteBusinessModeKill = false;

  bool get isBusinessModeEnabled {
    if (_remoteBusinessModeKill) return false;
    return ReleaseFlags.businessModeEnabled;
  }

  bool get isBusinessModeWriteEnabled => isBusinessModeEnabled;

  String get businessModeDisabledReason {
    if (_remoteBusinessModeKill) {
      return "Pro Mode has been temporarily disabled by remote rollout control.";
    }
    if (ReleaseFlags.businessModeForceOff) {
      return "Pro Mode has been force-disabled for this build.";
    }
    if (!ReleaseFlags.businessModeEnabled) {
      return "Pro Mode is coming soon.";
    }
    return "Pro Mode is available.";
  }

  Future<void> prime() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      return;
    }

    try {
      final FirebaseRemoteConfig rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 5),
          minimumFetchInterval: kReleaseMode
              ? const Duration(minutes: 15)
              : const Duration(seconds: 20),
        ),
      );
      await rc.setDefaults(const <String, Object>{
        _businessModeKillSwitchKey: false,
      });
      await rc.fetchAndActivate();
      _remoteBusinessModeKill = rc.getBool(_businessModeKillSwitchKey);
    } catch (e) {
      debugPrint("[RolloutGate] Remote Config unavailable: $e");
    }
  }
}
