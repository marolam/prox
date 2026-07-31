import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:prox/models/notification_item.dart";
import "package:prox/services/notification_feed_service.dart";
import "package:prox/services/user_settings_service.dart";

typedef MatchSoundPlayer = Future<void> Function(bool rare);

class MatchSignalService {
  MatchSignalService._();
  static final MatchSignalService instance = MatchSignalService._();

  DateTime? _lastAnySignalAt;
  DateTime? _lastRareSignalAt;
  String _lastTopUid = "";
  MatchSoundPlayer? _debugSoundPlayerOverride;

  static const Duration _minAnyGap = Duration(seconds: 12);
  static const Duration _minRareGap = Duration(seconds: 28);
  static const MethodChannel _soundChannel = MethodChannel("prox/match_sound");

  void onTopMatchChanged({
    required String uid,
    required int scorePercent,
    required String distanceLabel,
  }) {
    if (uid.trim().isEmpty) return;
    if (_lastTopUid == uid) return;

    _lastTopUid = uid;
    final settings = UserSettingsService.instance.current;
    final now = DateTime.now();

    if (settings.matchNotificationsEnabled) {
      final id = "match_signal_${uid}_${now.millisecondsSinceEpoch}";
      NotificationFeedService.instance.add(
        NotificationItem(
          id: id,
          type: "match",
          title: "New nearby match",
          body: "$distanceLabel • $scorePercent% fit",
          createdAtUtc: now.toUtc(),
          seen: false,
          data: <String, dynamic>{
            "type": "match",
            "uid": uid,
            "scorePercent": scorePercent,
            "distanceLabel": distanceLabel,
          },
        ),
      );
    }

    if (!settings.matchSoundEnabled) return;
    if (_lastAnySignalAt != null && now.difference(_lastAnySignalAt!) < _minAnyGap) {
      return;
    }
    _lastAnySignalAt = now;

    final bool rare = scorePercent >= 82;
    if (rare && settings.rareMatchSoundEnabled) {
      if (_lastRareSignalAt != null && now.difference(_lastRareSignalAt!) < _minRareGap) {
        _playSimple();
        return;
      }
      _lastRareSignalAt = now;
      _playRare();
      return;
    }

    _playSimple();
  }

  void _playSimple() {
    unawaited(_playMatchSound(rare: false));
  }

  void _playRare() {
    unawaited(_playMatchSound(rare: true));
  }

  Future<void> _playMatchSound({required bool rare}) async {
    final debugPlayer = _debugSoundPlayerOverride;
    if (debugPlayer != null) {
      await debugPlayer(rare);
      return;
    }

    try {
      final played = await _soundChannel.invokeMethod<bool>(
        "play",
        <String, bool>{"rare": rare},
      );
      if (played == true) return;
    } catch (_) {
      // Fall back below on platforms without the native tone bridge.
    }

    if (rare) {
      await _playRareFallback();
    } else {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _playRareFallback() async {
    unawaited(() async {
      await SystemSound.play(SystemSoundType.alert);
      await Future<void>.delayed(const Duration(milliseconds: 130));
      await SystemSound.play(SystemSoundType.click);
      await Future<void>.delayed(const Duration(milliseconds: 130));
      await SystemSound.play(SystemSoundType.alert);
    }());
  }

  @visibleForTesting
  void debugSetSoundPlayerForTesting(MatchSoundPlayer? player) {
    _debugSoundPlayerOverride = player;
  }

  @visibleForTesting
  void debugResetForTesting() {
    _lastAnySignalAt = null;
    _lastRareSignalAt = null;
    _lastTopUid = "";
    _debugSoundPlayerOverride = null;
  }
}
