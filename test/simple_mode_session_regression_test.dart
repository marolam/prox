import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:prox/services/simple_mode/simple_mode_policy.dart";

void main() {
  test("Simple Mode keeps only Big-5 home destinations interactive", () {
    expect(
      SimpleModePolicy.allowedHomeTabs,
      equals(<String>["Nearby", "Meetups", "Profile"]),
    );
  });

  test("matches are transient and have no user-accessible collection screen",
      () {
    final app = File("lib/app.dart").readAsStringSync();
    final router = File("lib/app_router.dart").readAsStringSync();
    final shell = File("lib/home/home_shell.dart").readAsStringSync();
    final rating =
        File("lib/screens/rating/rating_screen.dart").readAsStringSync();

    expect(app, isNot(contains('"/matches"')));
    expect(router, isNot(contains('matches = "/matches"')));
    expect(shell, isNot(contains('label: "Matches"')));
    expect(rating, contains('pushNamedAndRemoveUntil("/home"'));
  });

  test("completed meetup profiles require Party membership", () {
    final sessionBar =
        File("lib/widgets/meetup_session_bar.dart").readAsStringSync();

    expect(sessionBar, contains("isInMyParty(uid)"));
    expect(sessionBar, contains('status != "completed"'));
    expect(sessionBar, contains("!isPartyMember && !isActiveMeetup"));
  });

  test("successful Simple Mode meetup offers Party unlock and highlight", () {
    final rating =
        File("lib/screens/rating/rating_screen.dart").readAsStringSync();
    final shell = File("lib/home/home_shell.dart").readAsStringSync();
    final settings = File("lib/screens/services/user_settings_service.dart")
        .readAsStringSync();

    expect(rating, contains("Switch and add"));
    expect(rating, contains("unlockPartyFromSimpleMode()"));
    expect(settings, contains("partyUnlockHighlightPending: true"));
    expect(shell, contains('tabs[i].label == "Party"'));
    expect(shell, contains("setPartyUnlockHighlightPending(false)"));
  });

  test("home shell renders the complete tab list with disabled controls", () {
    final source = File("lib/home/home_shell.dart").readAsStringSync();
    expect(source, contains("List<_ShellTab> get _visibleTabs => _tabs"));
    expect(source, contains("enabled: _isTabEnabled(tabs[i])"));
    expect(source, contains("locked in Simple Mode"));
  });

  test("meetup screens persist and expose session navigation", () {
    final planner = File("lib/screens/meetup/meetup_planner_screen.dart")
        .readAsStringSync();
    final live =
        File("lib/screens/meetup/meetup_live_screen.dart").readAsStringSync();
    final recovery = File("lib/home/home_root_shell.dart").readAsStringSync();

    expect(planner, contains('screen: "planner"'));
    expect(live, contains('screen: "live"'));
    expect(recovery, contains("lastSessionScreen"));
    expect(recovery, contains("didChangeAppLifecycleState"));
  });
}
