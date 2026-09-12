import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:prox/services/match_signal_service.dart";
import "package:prox/services/user_settings_service.dart";

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    UserSettingsService.instance.setMatchNotificationsEnabled(false);
    UserSettingsService.instance.setMatchSoundEnabled(true);
    UserSettingsService.instance.setRareMatchSoundEnabled(true);
    MatchSignalService.instance.debugResetForTesting();
  });

  tearDown(() {
    MatchSignalService.instance.debugResetForTesting();
  });

  test("plays the normal match cue for ordinary matches", () async {
    final played = <bool>[];
    MatchSignalService.instance.debugSetSoundPlayerForTesting(
      (rare) async => played.add(rare),
    );

    MatchSignalService.instance.onTopMatchChanged(
      uid: "ordinary_match",
      scorePercent: 64,
      distanceLabel: "Nearby",
    );
    await Future<void>.delayed(Duration.zero);

    expect(played, <bool>[false]);
  });

  test("plays the rare match cue for high-confidence matches", () async {
    final played = <bool>[];
    MatchSignalService.instance.debugSetSoundPlayerForTesting(
      (rare) async => played.add(rare),
    );

    MatchSignalService.instance.onTopMatchChanged(
      uid: "rare_match",
      scorePercent: 90,
      distanceLabel: "Nearby",
    );
    await Future<void>.delayed(Duration.zero);

    expect(played, <bool>[true]);
  });

  test("falls back to the normal cue when rare match sound is disabled", () async {
    UserSettingsService.instance.setRareMatchSoundEnabled(false);
    final played = <bool>[];
    MatchSignalService.instance.debugSetSoundPlayerForTesting(
      (rare) async => played.add(rare),
    );

    MatchSignalService.instance.onTopMatchChanged(
      uid: "muted_rare_match",
      scorePercent: 90,
      distanceLabel: "Nearby",
    );
    await Future<void>.delayed(Duration.zero);

    expect(played, <bool>[false]);
  });

  test("stays silent when match sound is disabled", () async {
    UserSettingsService.instance.setMatchSoundEnabled(false);
    final played = <bool>[];
    MatchSignalService.instance.debugSetSoundPlayerForTesting(
      (rare) async => played.add(rare),
    );

    MatchSignalService.instance.onTopMatchChanged(
      uid: "silent_match",
      scorePercent: 92,
      distanceLabel: "Nearby",
    );
    await Future<void>.delayed(Duration.zero);

    expect(played, isEmpty);
  });
}