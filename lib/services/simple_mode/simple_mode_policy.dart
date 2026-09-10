import "package:prox/models/user_settings.dart";
import "package:prox/services/user_settings_service.dart";

/// The product-level restrictions for the repeatable Simple Mode experience.
class SimpleModePolicy {
  const SimpleModePolicy._();

  static bool get isActive {
    final settings = UserSettingsService.instance.current;
    return settings.simpleModeEnabled && !settings.alwaysUseNormalMode;
  }

  static const List<String> allowedHomeTabs = <String>[
    "Nearby",
    "Meetups",
    "Profile",
  ];

  static MatchDiscoverySettings lockedDiscoveryDefaults(
    MatchDiscoverySettings current,
  ) {
    return const MatchDiscoverySettings.defaults().copyWith(
      normalMode: current.normalMode,
      activeLockUntilEpochMs: current.activeLockUntilEpochMs,
      activePenaltyCount: current.activePenaltyCount,
    );
  }

  static SimpleModeGuidance guidanceFor(String tab) {
    switch (tab) {
      case "Profile":
        return const SimpleModeGuidance(
          step: "1 of 5",
          title: "Build your profile",
          message:
              "Add your name, photo, what you are looking for, and what you can provide. Accurate keywords power every match.",
        );
      case "Nearby":
        return const SimpleModeGuidance(
          step: "2-3 of 5",
          title: "Find a match and say hello",
          message:
              "Use Active when searching now or Passive to remain available. Tap a current match card, say hello, and confirm that you both want the same thing. Missed matches are not saved.",
        );
      case "Meetups":
        return const SimpleModeGuidance(
          step: "4-5 of 5",
          title: "Meet safely, then rate",
          message:
              "Plan and complete the meetup here. Submit your rating afterward to finish the Big-5, then return to Profile or Nearby and repeat.",
        );
      default:
        return const SimpleModeGuidance(
          step: "Big-5",
          title: "Complete the next action",
          message: "Follow the available actions to continue the Big-5 loop.",
        );
    }
  }
}

class SimpleModeGuidance {
  const SimpleModeGuidance({
    required this.step,
    required this.title,
    required this.message,
  });

  final String step;
  final String title;
  final String message;
}
