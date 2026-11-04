import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:prox/widgets/profile_keyword_chip.dart";

void main() {
  testWidgets("keyword activation and removal are separate actions", (
    tester,
  ) async {
    var toggles = 0;
    var removals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileKeywordChip(
            keyword: "gardening",
            active: true,
            accentColor: Colors.teal,
            onToggle: () => toggles++,
            onRemove: () => removals++,
          ),
        ),
      ),
    );
    await tester.tap(find.text("gardening"));
    expect(toggles, 1);
    expect(removals, 0);
    await tester.tap(find.byTooltip("Remove gardening"));
    expect(toggles, 1);
    expect(removals, 1);
    expect(tester.widget<InputChip>(find.byType(InputChip)).selected, isTrue);
  });

  testWidgets("inactive keywords can also be removed", (tester) async {
    var removed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => removed
                ? const Text("No keywords yet.")
                : ProfileKeywordChip(
                    keyword: "gardening",
                    active: false,
                    accentColor: Colors.teal,
                    onToggle: () {},
                    onRemove: () => setState(() => removed = true),
                  ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip("Remove gardening"));
    await tester.pumpAndSettle();
    expect(find.text("gardening"), findsNothing);
    expect(find.text("No keywords yet."), findsOneWidget);
  });

  testWidgets("saving disables both keyword actions", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileKeywordChip(
            keyword: "gardening",
            active: true,
            accentColor: Colors.teal,
            onToggle: null,
            onRemove: null,
          ),
        ),
      ),
    );
    final chip = tester.widget<InputChip>(find.byType(InputChip));
    expect(chip.onPressed, isNull);
    expect(chip.onDeleted, isNull);
    expect(find.byTooltip("Remove gardening"), findsNothing);
  });

  testWidgets("remove stays accessible on narrow screens with large text", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: SizedBox(
              width: 288,
              child: Wrap(
                children: [
                  ProfileKeywordChip(
                    keyword: "home improvement",
                    active: false,
                    accentColor: Colors.teal,
                    onToggle: _noop,
                    onRemove: _noop,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip("Remove home improvement"), findsOneWidget);
    await tester.tap(find.byTooltip("Remove home improvement"));
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
