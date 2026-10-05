import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/models/user_settings.dart";
import "package:prox/screens/services/user_settings_service.dart";
import "package:prox/screens/simple_mode/simple_mode_choice_screen.dart";

void main() {
  group("Simple mode gate regression", () {
    testWidgets(
        "mode choice screen is unpassable and emits expected normal-mode preference",
        (tester) async {
      bool simpleSelected = false;
      bool? normalAlways;

      await tester.pumpWidget(
        MaterialApp(
          home: SimpleModeChoiceScreen(
            onSelectSimple: () {
              simpleSelected = true;
            },
            onSelectNormal: (alwaysUseNormal) {
              normalAlways = alwaysUseNormal;
            },
          ),
        ),
      );

      final popScope = tester.widget<PopScope<void>>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);

      final listView = find.byType(ListView);
      await tester.dragUntilVisible(
        find.text("Continue in Normal Mode"),
        listView,
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("Continue in Normal Mode"));
      await tester.pumpAndSettle();
      expect(normalAlways, isFalse);
      expect(simpleSelected, isFalse);

      await tester.tap(find.text("Always use Normal Mode"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Continue in Normal Mode"));
      await tester.pumpAndSettle();
      expect(normalAlways, isTrue);
      expect(simpleSelected, isFalse);

      await tester.dragUntilVisible(
        find.text("Use Simple Mode"),
        listView,
        const Offset(0, 250),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("Use Simple Mode"));
      await tester.pumpAndSettle();
      expect(simpleSelected, isTrue);
    });

    test("auth gate defaults fresh users directly into Simple Mode", () {
      final source = File("lib/screens/auth/auth_gate.dart").readAsStringSync();
      expect(source, contains("child: const _ExperienceModeGate("));
      expect(source, isNot(contains("return SimpleModeChoiceScreen(")));
      expect(source, isNot(contains("SimpleModeWalkthroughScreen")));
      expect(source, contains("setSimpleModeEnabled(true)"));
      expect(source, contains("setSimpleModeCompleted(true)"));
      expect(
          source, contains("setState(() => _view = _ExperienceGateView.home)"));
    });

    test("simple mode stage index clamps to the valid progression range", () {
      final service = UserSettingsService.forTesting();

      service.setSimpleModeStageIndex(-12);
      expect(service.current.simpleModeStageIndex, 0);

      service.setSimpleModeStageIndex(99);
      expect(service.current.simpleModeStageIndex, 5);
    });

    test("user settings copyWith clamps the simple mode stage index", () {
      final settings = const UserSettings.defaults();

      final low = settings.copyWith(simpleModeStageIndex: -12);
      expect(low.simpleModeStageIndex, 0);

      final high = settings.copyWith(simpleModeStageIndex: 99);
      expect(high.simpleModeStageIndex, 5);
    });
  });
}
