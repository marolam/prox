import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/screens/settings/support_feedback_screen.dart";
import "package:prox/services/feedback_service.dart";

void main() {
  Widget wrap({FeedbackSubmitter? submitFeedback}) {
    return MaterialApp(
      home: SupportFeedbackScreen(submitFeedback: submitFeedback),
    );
  }

  testWidgets("send stays disabled until note has non-whitespace text", (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    FilledButton sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, "Send"),
    );
    expect(sendButton.onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, "What broke?"),
      "   ",
    );
    await tester.pump();

    sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, "Send"),
    );
    expect(sendButton.onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, "What broke?"),
      "Map jump",
    );
    await tester.pump();

    sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, "Send"),
    );
    expect(sendButton.onPressed, isNotNull);
  });

  testWidgets("locks controls while sending, then clears and shows success", (
    tester,
  ) async {
    final completer = Completer<void>();

    await tester.pumpWidget(
      wrap(
        submitFeedback:
            ({
              required ProxFeedbackType type,
              required String text,
              String? firstHuhMoment,
              String source = "in_app",
            }) {
              return completer.future;
            },
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, "What broke?"),
      "Nearby list is stale",
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, "Send"));
    await tester.pump();

    expect(find.text("Sending..."), findsOneWidget);

    final messageField = tester.widget<TextField>(
      find.widgetWithText(TextField, "What broke?"),
    );
    final huhField = tester.widget<TextField>(
      find.widgetWithText(TextField, "First confusion moment (optional)"),
    );
    expect(messageField.enabled, isFalse);
    expect(huhField.enabled, isFalse);

    final elaborateButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, "Elaborate"),
    );
    expect(elaborateButton.onPressed, isNull);

    completer.complete();
    await tester.pump();

    expect(find.text("Sending..."), findsNothing);
    expect(find.text("Bug Report sent. Thank you."), findsOneWidget);

    final messageFieldAfter = tester.widget<TextField>(
      find.widgetWithText(TextField, "What broke?"),
    );
    expect(messageFieldAfter.controller?.text, isEmpty);
    expect(messageFieldAfter.enabled, isTrue);
  });

  testWidgets("shows stable retry message on submit failure", (tester) async {
    await tester.pumpWidget(
      wrap(
        submitFeedback:
            ({
              required ProxFeedbackType type,
              required String text,
              String? firstHuhMoment,
              String source = "in_app",
            }) async {
              throw StateError("backend unavailable");
            },
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, "What broke?"),
      "Map jump flicker",
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, "Send"));
    await tester.pump();

    expect(
      find.text(
        'Submission could not be confirmed. Retry with this saved draft; it will keep the same report reference.',
      ),
      findsOneWidget,
    );
  });
}
