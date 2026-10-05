import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:prox/screens/settings/sound_alert_settings_screen.dart";
import "package:prox/services/user_settings_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SoundAlertSettingsScreen()),
    );
    await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = UserSettingsService.instance;
    settings.setMatchNotificationsEnabled(true);
    settings.setMatchSoundEnabled(true);
    settings.setRareMatchSoundEnabled(true);
    settings.setMatchSoundVolume(0.6);
  });

  testWidgets("shows preview hint when match sounds are disabled", (
    tester,
  ) async {
    UserSettingsService.instance.setMatchSoundEnabled(false);

    await pumpScreen(tester);

    expect(find.text("Enable Match sounds to preview cues."), findsOneWidget);
    expect(find.text("Turn on Match sounds to use this cue."), findsOneWidget);
    expect(
      find.text("High-fit cue is paused while Match sounds is off."),
      findsOneWidget,
    );
    final standardButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, "Standard match"),
    );
    expect(standardButton.onPressed, isNull);
  });

  testWidgets("shows preview hint when volume is zero", (tester) async {
    UserSettingsService.instance.setMatchSoundEnabled(true);
    UserSettingsService.instance.setMatchSoundVolume(0);

    await pumpScreen(tester);

    expect(
      find.text("Increase in-app sound volume above 0% to preview cues."),
      findsOneWidget,
    );
    final standardButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, "Standard match"),
    );
    expect(standardButton.onPressed, isNull);
  });

  testWidgets("hides preview hint when previews are available", (tester) async {
    UserSettingsService.instance.setMatchSoundEnabled(true);
    UserSettingsService.instance.setMatchSoundVolume(0.7);

    await pumpScreen(tester);

    expect(find.text("Enable Match sounds to preview cues."), findsNothing);
    expect(
      find.text("Increase in-app sound volume above 0% to preview cues."),
      findsNothing,
    );
    expect(find.text("Turn on Match sounds to use this cue."), findsNothing);
    expect(
      find.text("High-fit cue is paused while Match sounds is off."),
      findsNothing,
    );
  });
}
