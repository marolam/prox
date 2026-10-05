import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/widgets/match_chat_request_actions.dart';

void main() {
  Future<void> showActions(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
    required Future<void> Function() accept,
    required Future<void> Function() decline,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: width,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: MatchChatRequestActions(
                  onAccept: accept,
                  onDecline: decline,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('large labelled actions fit narrow cards and enlarged text', (
    tester,
  ) async {
    var declines = 0;
    for (final width in [260.0, 400.0]) {
      for (final scale in [1.0, 2.0]) {
        await showActions(
          tester,
          width: width,
          textScale: scale,
          accept: () async {},
          decline: () async {
            declines++;
          },
        );
        expect(find.text('Your next step: respond'), findsOneWidget);
        expect(find.text('Accept chat'), findsOneWidget);
        expect(find.text('Decline chat'), findsOneWidget);
        expect(
          tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(56),
        );
        expect(
          tester.getSize(find.byType(OutlinedButton)).height,
          greaterThanOrEqualTo(56),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Decline chat'));
        await tester.tap(find.text('Decline chat'));
        await tester.pump();
      }
    }
    expect(declines, 4);
  });

  testWidgets(
    'an in-flight response disables both actions until it completes',
    (tester) async {
      final pending = Completer<void>();
      var accepts = 0;
      var declines = 0;
      await showActions(
        tester,
        width: 300,
        accept: () {
          accepts++;
          return pending.future;
        },
        decline: () async {
          declines++;
        },
      );
      await tester.tap(find.text('Accept chat'));
      await tester.pump();
      expect(find.text('Accepting…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(accepts, 1);
      expect(declines, 0);
      pending.complete();
      await tester.pump();
      expect(find.text('Accept chat'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
    },
  );
}
