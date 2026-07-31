import "package:flutter/material.dart";

import "package:prox/home/home_root_shell.dart";
import "package:prox/models/color_match_models.dart";
import "package:prox/screens/account/account_billing_screen.dart";
import "package:prox/screens/business/business_mode_entry_screen.dart";
import "package:prox/screens/business/business_mode_setup_screen.dart";
import "package:prox/screens/meetup/color_match_screen.dart";
import "package:prox/screens/matches/matches_screen.dart";
import "package:prox/screens/chats/chat_threads_screen.dart";
import "package:prox/screens/onboarding/onboarding_screen.dart";
import "package:prox/screens/store/prox_points_store_screen.dart";
import "package:prox/screens/support/support_hub_screen.dart";
import "package:prox/screens/referral/referrals_hub_screen.dart";
import "package:prox/screens/review/tester_mission_screen.dart";
import "package:prox/screens/tester/tester_insight_mode_screen.dart";

class AppRouter {
  // Common route names used across the app.
  static const String auth = "/auth";
  static const String onboarding = "/onboarding";
  static const String home = "/home";
  static const String inbox = "/inbox";
  static const String matches = "/matches";
  static const String dashboard = "/dashboard";
  static const String store = "/store";
  static const String support = "/support";
  static const String referrals = "/referrals";
  static const String account = "/account";
  static const String testerMission = "/tester-mission";
  static const String testerInsight = "/tester-insight";
  static const String businessMode = "/business-mode";
  static const String businessSetup = "/business-setup";
  static const String colorMatch = "/color-match";

  static Route<dynamic> toOnboarding() =>
      MaterialPageRoute(builder: (_) => const OnboardingScreen());

  static Route<dynamic> toHome() =>
      MaterialPageRoute(builder: (_) => const HomeRootShell());

  static Route<dynamic> toMatches() =>
      MaterialPageRoute(builder: (_) => const MatchesScreen());

    static Route<dynamic> toInbox() =>
      MaterialPageRoute(builder: (_) => const ChatThreadsScreen());

  static Route<dynamic> toAccount() =>
      MaterialPageRoute(builder: (_) => const AccountBillingScreen());

  static Route<dynamic> toSupport() =>
      MaterialPageRoute(builder: (_) => const SupportHubScreen());

  static Route<dynamic> toReferrals() =>
      MaterialPageRoute(builder: (_) => const ReferralsHubScreen());

  static Route<dynamic> toTesterMission() =>
      MaterialPageRoute(builder: (_) => const TesterMissionScreen());

    static Route<dynamic> toTesterInsight() =>
      MaterialPageRoute(builder: (_) => const TesterInsightModeScreen());

  static Route<dynamic> toBusinessMode() =>
      MaterialPageRoute(builder: (_) => const BusinessModeEntryScreen());

  static Route<dynamic> toBusinessSetup() =>
      MaterialPageRoute(builder: (_) => const BusinessModeSetupScreen());

  static Route<dynamic> toStore() =>
      MaterialPageRoute(builder: (_) => const ProxPointsStoreScreen());

  static Route<dynamic> toColorMatch({
    MatchColor? initialColor,
    String meetupId = "demo",
    VoidCallback? onDismiss,
  }) {
    return MaterialPageRoute(
      builder: (_) => ColorMatchScreen(
        initialColor: initialColor ?? MatchColor.values.first,
        meetupId: meetupId,
        onDismiss: onDismiss ?? () {},
      ),
    );
  }
}





