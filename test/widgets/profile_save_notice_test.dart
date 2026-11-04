import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:prox/widgets/profile_save_notice.dart";

void main() {
  testWidgets("notice identifies unsaved changes and the save button", (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfileSaveNotice())),
    );
    expect(
      find.text(
        'You have unsaved changes. Tap "Save Profile" to save your changes.',
      ),
      findsOneWidget,
    );
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(ProfileSaveNotice),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.liveRegion, isTrue);
  });

  testWidgets("notice wraps on narrow screens with large text", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(width: 280, child: ProfileSaveNotice()),
          ),
        ),
      ),
    );
    expect(find.text(ProfileSaveNotice.message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
