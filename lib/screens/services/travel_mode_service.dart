import "dart:async";

import "package:prox/services/motion_classifier.dart";
import "package:prox/services/presence_writer.dart";
import "package:prox/services/travel_analytics_service.dart";

class TravelStatus {
  final MotionState motion;
  final double speedMps;
  final DateTime ts;
  final bool isTraveling;

  const TravelStatus({
    required this.motion,
    required this.speedMps,
    required this.ts,
    required this.isTraveling,
  });
}

class TravelModeService {
  TravelModeService._() {
    _sub = PresenceWriter.instance.motionStream.listen(
      _handleSnapshot,
      onError: (_) {},
    );
  }

  static final TravelModeService instance = TravelModeService._();

  final StreamController<TravelStatus> _statusController =
      StreamController<TravelStatus>.broadcast();

  StreamSubscription<MotionSnapshot>? _sub;

  TravelStatus? _latest;
  TravelStatus? get latest => _latest;

  Stream<TravelStatus> get stream => _statusController.stream;

  void _handleSnapshot(MotionSnapshot snap) {
    final motion = snap.motion;
    final speed = snap.speedMps;

    final bool traveling = _isTraveling(motion, speed);

    _latest = TravelStatus(
      motion: motion,
      speedMps: speed,
      ts: snap.ts,
      isTraveling: traveling,
    );

    TravelAnalyticsService.instance.handleSample(
      ts: snap.ts,
      isTraveling: traveling,
    );

    if (!_statusController.isClosed) {
      _statusController.add(_latest!);
    }
  }

  bool _isTraveling(MotionState motion, double speedMps) {
    switch (motion) {
      case MotionState.driving:
        return true;
      case MotionState.walking:
        return speedMps > 1.5;
      case MotionState.moving:
        // Generic "moving" bucket: treat as traveling above a modest threshold.
        return speedMps > 1.0;
      case MotionState.stationary:
        return false;
      case MotionState.unknown:
        return false;
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _statusController.close();
  }
}
