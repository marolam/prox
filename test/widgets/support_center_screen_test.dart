import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:prox/screens/support/support_center_screen.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> _seedDraftStorage() {
    final payload = jsonEncode([
      {
        "id": "draft-1",
        "subject": "Map marker issue",
        "message": "   ",
        "createdAt": DateTime.utc(2026, 9, 26, 12, 30).toIso8601String(),
        "updatedAt": DateTime.utc(2026, 9, 26, 12, 31).toIso8601String(),
      },
    ]);

    return <String, Object>{"support.drafts.v1.guest": payload};
  }

  Future<void> _pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SupportCenterScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets("delete confirmation supports cancel and confirm", (tester) async {
    SharedPreferences.setMockInitialValues(_seedDraftStorage());
    await _pumpScreen(tester);

    expect(find.text("Map marker issue"), findsOneWidget);
    expect(
      find.text("No details yet. Tap to continue this draft."),
      findsOneWidget,
    );
    expect(find.textContaining("Last edited \u2022 "), findsOneWidget);

    final deleteIcon = find.byIcon(Icons.delete_outline);
    await tester.scrollUntilVisible(deleteIcon, 300);
    await tester.tap(deleteIcon.first);
    await tester.pumpAndSettle();

    expect(find.text("Delete draft?"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();

    expect(find.text("Map marker issue"), findsOneWidget);

    await tester.tap(deleteIcon.first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, "Delete"));
    await tester.pumpAndSettle();

    expect(find.text("Map marker issue"), findsNothing);
    expect(
      find.text(
        "No drafts yet. Start a support message and it will appear here until you send or delete it.",
      ),
      findsOneWidget,
    );
  });
}
