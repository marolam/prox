import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/screens/settings/user_guide_screen.dart";

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: UserGuideScreen()),
    );
    await tester.pump();
  }

  testWidgets("search ignores punctuation and casing", (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextField, "Search the guide"),
      "SUPPORT!!!",
    );
    await tester.pump();

    expect(find.textContaining("topics found"), findsOneWidget);
    expect(find.text("Get support or share an idea"), findsOneWidget);
    expect(find.text("Get better nearby matches"), findsNothing);
  });

  testWidgets("clear search action resets query and restores full list", (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextField, "Search the guide"),
      "ticket dashboard",
    );
    await tester.pump();

    expect(find.byTooltip("Clear search"), findsOneWidget);
    expect(
      find.text("No topics found. Try “matches”, “privacy”, or “support”."),
      findsNothing,
    );

    await tester.tap(find.byTooltip("Clear search"));
    await tester.pump();

    expect(find.byTooltip("Clear search"), findsNothing);
    expect(find.text("1 topic found"), findsNothing);
    expect(find.textContaining("topics found"), findsNothing);
    expect(find.text("Start here: the Prox journey"), findsOneWidget);
    expect(
      find.text("No topics found. Try “matches”, “privacy”, or “support”."),
      findsNothing,
    );
  });

  testWidgets("no-results copy still appears for unmatched queries", (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextField, "Search the guide"),
      "xyz-unmatched-topic",
    );
    await tester.pump();

    expect(find.text("0 topics found"), findsOneWidget);
    expect(
      find.text("No topics found. Try “matches”, “privacy”, or “support”."),
      findsOneWidget,
    );
  });
}
