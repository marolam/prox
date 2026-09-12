import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:prox/widgets/chat_gate_banner.dart";

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets("shows pending actions only for explicit requested status", (tester) async {
    await tester.pumpWidget(
      wrap(
        ChatGateBanner(
          isParty: false,
          myUid: "me",
          status: "requested",
          requestedBy: "other",
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );

    expect(find.text("Accept"), findsOneWidget);
    expect(find.text("Decline"), findsOneWidget);
  });

  testWidgets("hides request actions after accepted", (tester) async {
    await tester.pumpWidget(
      wrap(
        ChatGateBanner(
          isParty: false,
          myUid: "me",
          status: "accepted",
          requestedBy: "other",
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );

    expect(find.text("Accept"), findsNothing);
    expect(find.text("Decline"), findsNothing);
  });

  testWidgets("hides request actions when status is empty", (tester) async {
    await tester.pumpWidget(
      wrap(
        ChatGateBanner(
          isParty: false,
          myUid: "me",
          status: "",
          requestedBy: "",
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );

    expect(find.text("Accept"), findsNothing);
    expect(find.text("Decline"), findsNothing);
  });

  testWidgets("requested-by-me state does not show accept or decline buttons", (tester) async {
    await tester.pumpWidget(
      wrap(
        ChatGateBanner(
          isParty: false,
          myUid: "me",
          status: "requested",
          requestedBy: "me",
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );

    expect(find.text("Chat request sent. Waiting for them to accept..."), findsOneWidget);
    expect(find.text("Accept"), findsNothing);
    expect(find.text("Decline"), findsNothing);
  });
}
