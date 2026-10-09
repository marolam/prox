import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/widgets/referral_mentor_card.dart';
import 'package:prox/services/party_service.dart';

void main() {
  test(
    'mentor Party contacts never masquerade as in-person mutual members',
    () {
      final contact = PartyMemberEntry.fromDoc('mentor', {
        'mutual': true,
        'metInPerson': false,
        'source': 'referralMentor',
      });
      expect(contact.isMentorContact, isTrue);
      expect(contact.mutual, isFalse);
      final verified = PartyMemberEntry.fromDoc('mentor', {
        'mutual': true,
        'metInPerson': true,
        'source': 'postMeetup',
      });
      expect(verified.isMentorContact, isFalse);
      expect(verified.mutual, isTrue);
    },
  );

  testWidgets(
    'mentor reminder remains visible and support is actionable without a Party contact',
    (tester) async {
      String? route;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReferralMentorCard(
              uid: 'newbie',
              mentorStream: Stream.value({
                'mentorUid': 'mentor',
                'displayName': 'Helpful friend',
                'partyAdded': false,
                'lastNudge': 'Your mentor suggests support if you need help.',
              }),
            ),
          ),
          onGenerateRoute: (settings) {
            route = settings.name;
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Support')),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your referrer / mentor'), findsOneWidget);
      expect(find.text('Helpful friend'), findsOneWidget);
      expect(find.text('Message mentor'), findsNothing);
      expect(
        find.text('Your mentor suggests support if you need help.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Contact support'));
      await tester.pumpAndSettle();
      expect(route, '/support');
    },
  );

  testWidgets('profile-ready Party contacts expose the mentor message action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferralMentorCard(
            uid: 'newbie',
            mentorStream: Stream.value({
              'mentorUid': 'mentor',
              'partyAdded': true,
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message mentor'), findsOneWidget);
  });
}
