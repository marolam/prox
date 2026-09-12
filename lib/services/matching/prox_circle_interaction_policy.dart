import "package:prox/models/user_settings.dart";

class ProxCircleInteractionPolicy {
  ProxCircleInteractionPolicy._();

  static const List<MatchingModeKind> cycleOrder = <MatchingModeKind>[
    MatchingModeKind.normal,
    MatchingModeKind.listen,
    MatchingModeKind.treasureHunt,
    MatchingModeKind.travel,
    MatchingModeKind.off,
  ];

  static bool canCycle({
    required MatchDiscoverySettings discovery,
    required bool sessionUnlocked,
  }) {
    if (sessionUnlocked) return true;
    if (discovery.modeKind == MatchingModeKind.normal) {
      return discovery.normalMode == NormalMatchMode.active;
    }
    return discovery.modeKind != MatchingModeKind.off;
  }

  static MatchingModeKind nextMode(MatchingModeKind current) {
    final index = cycleOrder.indexOf(current);
    return cycleOrder[index < 0 ? 0 : (index + 1) % cycleOrder.length];
  }

  static bool shouldSuppressTap({
    required DateTime now,
    required DateTime? suppressUntil,
  }) {
    return suppressUntil != null && now.isBefore(suppressUntil);
  }
}
