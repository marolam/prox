import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/screens/simple_mode/simple_mode_walkthrough_screen.dart";

void main() {
  testWidgets("walkthrough exposes progress to assistive technology",
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: SimpleModeWalkthroughScreen(onDone: () {}),
      ),
    );

    expect(
      tester.getSemantics(find.byType(LinearProgressIndicator)),
      matchesSemantics(
        label: "Simple Mode setup progress",
        value: "Step 1 of 5",
      ),
    );

    semantics.dispose();
  });

  testWidgets("continue is disabled while a page transition is running",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SimpleModeWalkthroughScreen(onDone: () {}),
      ),
    );

    await tester.tap(find.text("Continue"));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.pumpAndSettle();
    expect(find.text("Step 2 of 5"), findsOneWidget);
    expect(find.text("Step 3 of 5"), findsNothing);
  });
}
