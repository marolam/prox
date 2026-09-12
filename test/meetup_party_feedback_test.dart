import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/party_connection_service.dart';
import 'package:prox/widgets/meetup_rating_form.dart';
import 'package:prox/widgets/pending_party_requests.dart';
import 'package:prox/screens/party/party_member_profile_screen.dart';
import 'package:prox/screens/services/party_profile_service.dart';
import 'package:prox/screens/services/user_profile_service.dart';

void main() {
  Future<void> form(
    WidgetTester tester,
    SaveMeetupRating save, {
    bool simple = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MeetupRatingForm(save: save, partyRequiresNormalMode: simple),
        ),
      ),
    ),
  );
  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'thumbs up reveals two choices; cancelling confirmation saves nothing',
    (tester) async {
      var calls = 0;
      await form(tester, (thumb, choice, comment) async {
        calls++;
        return 'pending';
      });
      expect(find.text('Add to Party'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      await tester.tap(find.byTooltip('Thumbs up'));
      await tester.pumpAndSettle();
      expect(find.text('Add to Party'), findsOneWidget);
      expect(find.text('Not Right Now'), findsOneWidget);
      await tester.tap(find.text('Add to Party'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Party Visible'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('Add to Party'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Add to Party');
      expect(calls, 1);
      expect(find.textContaining('Rating saved.'), findsOneWidget);
    },
  );
  testWidgets('Not Right Now saves a positive rating without consent', (
    tester,
  ) async {
    final calls = <Object>[];
    await form(tester, (up, choice, comment) async {
      calls.add([up, choice, comment]);
      return 'pending';
    });
    await tester.tap(find.byTooltip('Thumbs up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not Right Now'));
    await tester.pumpAndSettle();
    await confirm(tester, 'Not Right Now');
    expect(calls, [
      [true, 'later', ''],
    ]);
  });
  for (final comment in ['', 'Something felt wrong']) {
    testWidgets('thumbs down opens optional comment and submits "$comment"', (
      tester,
    ) async {
      final calls = <Object>[];
      await form(tester, (up, choice, note) async {
        calls.add([up, choice, note]);
        return 'rated';
      });
      await tester.tap(find.byTooltip('Thumbs down'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      if (comment.isNotEmpty)
        await tester.enterText(find.byType(TextField), comment);
      await tester.tap(find.text('Submit feedback'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(calls, [
        [false, 'later', comment],
      ]);
      expect(find.text('Your feedback is saved.'), findsOneWidget);
    });
  }
  testWidgets('save failures are visible and can be retried', (tester) async {
    var calls = 0;
    await form(tester, (up, choice, comment) async {
      if (++calls == 1)
        throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'Please reconnect and retry.',
        );
      return 'connected';
    });
    await tester.tap(find.byTooltip('Thumbs up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Party'));
    await tester.pumpAndSettle();
    await confirm(tester, 'Add to Party');
    expect(find.text('Please reconnect and retry.'), findsOneWidget);
    await tester.tap(find.text('Add to Party'));
    await tester.pumpAndSettle();
    await confirm(tester, 'Add to Party');
    expect(find.textContaining('You are now in each'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets('Simple Mode confirmation explains the mode change', (
    tester,
  ) async {
    await form(tester, (_, _, _) async => 'pending', simple: true);
    await tester.tap(find.byTooltip('Thumbs up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Party'));
    await tester.pumpAndSettle();
    expect(find.textContaining('switches you to Normal Mode'), findsOneWidget);
  });
  testWidgets(
    'pending Remind and Block require confirmation and report errors',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingPartyRequestCard(
              name: 'Taylor',
              connection: PendingPartyConnection(
                otherUid: 'bob',
                myDecision: 'add',
                theirDecision: 'later',
                expiresAt: DateTime.now().add(const Duration(days: 7)),
              ),
              onAction: (action) async {
                calls.add(action);
                return 'pending';
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Remind'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.text('Remind'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Remind');
      expect(calls, ['remind']);
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(find.textContaining('prevents further requests'), findsOneWidget);
      await confirm(tester, 'Block');
      expect(calls, ['remind', 'block']);
    },
  );
  test('pending expiry and reminder cooldown use activity timestamps', () {
    final now = DateTime.utc(2026, 9, 12);
    final p = PendingPartyConnection.fromMap({
      'members': ['alice', 'bob'],
      'status': 'pending',
      'decisions': {'alice': 'add'},
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
      'reminders': {'alice': Timestamp.fromDate(now)},
    }, 'alice')!;
    expect(p.canRemind(now.add(const Duration(hours: 23))), false);
    expect(p.canRemind(now.add(const Duration(days: 1))), true);
    expect(p.isActive(now.add(const Duration(days: 7))), false);
  });
  testWidgets(
    'all selected Party profile fields display and membership loss revokes them',
    (tester) async {
      final membership = StreamController<bool>.broadcast();
      final profile = Stream<UserProfile?>.value(
        const UserProfile(
          uid: 'bob',
          displayName: 'Taylor',
          headline: 'Builder',
          searchingFor: ['Tools'],
          canProvide: ['Repairs'],
        ),
      );
      final sharing = Stream<PartyProfileSharing>.value(
        const PartyProfileSharing(
          about: 'About Taylor',
          phone: '555-0100',
          contactEmail: 'taylor@example.test',
          generalArea: 'Downtown',
          shareAbout: true,
          sharePhone: true,
          shareContactEmail: true,
          shareGeneralArea: true,
          shareHeadline: true,
          shareKeywords: true,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PartyMemberProfileScreen(
            memberUid: 'bob',
            membershipStream: membership.stream,
            profileStream: profile,
            sharingStream: sharing,
          ),
        ),
      );
      membership.add(true);
      await tester.pumpAndSettle();
      for (final text in [
        'Builder',
        'About Taylor',
        'Downtown',
        'Tools',
        'Repairs',
        'taylor@example.test',
        '555-0100',
      ]) {
        await tester.scrollUntilVisible(
          find.text(text),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(text), findsOneWidget);
      }
      membership.add(false);
      await tester.pumpAndSettle();
      expect(find.text('555-0100'), findsNothing);
      expect(find.textContaining('only to Party members'), findsOneWidget);
      await membership.close();
    },
  );
  testWidgets('negative comment is retained after a failed save', (
    tester,
  ) async {
    await form(
      tester,
      (_, _, _) async => throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Reconnect to retry.',
      ),
    );
    await tester.tap(find.byTooltip('Thumbs down'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Please keep these details');
    await tester.tap(find.text('Submit feedback'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Thumbs down'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Please keep these details',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
  });
}
