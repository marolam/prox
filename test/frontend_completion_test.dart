import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prox/models/support_ticket_draft.dart';
import 'package:prox/services/support_ticket_queue.dart';
import 'package:prox/services/support_email.dart';
import 'package:prox/widgets/progress_checklist_screen.dart';
import 'package:prox/screens/settings/user_guide_screen.dart';
import 'package:prox/screens/store/feature_example_screen.dart';
import 'package:prox/dev/dev_user_simulator_screen.dart';
import 'package:prox/screens/dev/dev_points_demo_screen.dart';
import 'package:prox/screens/support/support_hub_screen.dart';
import 'package:prox/screens/business/business_mode_screen.dart';
import 'package:prox/screens/business/business_mode_setup_screen.dart';
import 'package:prox/screens/business/business_profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  SupportTicketDraft draft(String id) => SupportTicketDraft(
    id: id,
    subject: 'Subject $id',
    message: 'Saved support message $id',
    createdAt: DateTime.utc(2026, 9, 8),
  );

  test(
    'support drafts survive restart and concurrent writes without dropping entries',
    () async {
      final queue = SupportTicketQueue.forTesting(ownerId: () => 'alice');
      await Future.wait([
        for (var i = 0; i < 12; i++) queue.upsertDraft(draft('$i')),
      ]);
      expect(queue.drafts, hasLength(12));
      queue.dispose();
      final restored = SupportTicketQueue.forTesting(ownerId: () => 'alice');
      await restored.ensureLoaded();
      expect(restored.drafts.map((d) => d.id).toSet(), {
        for (var i = 0; i < 12; i++) '$i',
      });
      await restored.removeDraft('3');
      restored.dispose();
      final reopened = SupportTicketQueue.forTesting(ownerId: () => 'alice');
      await reopened.ensureLoaded();
      expect(reopened.drafts, hasLength(11));
      expect(reopened.drafts.any((d) => d.id == '3'), isFalse);
      reopened.dispose();
    },
  );

  test(
    'switching accounts cannot expose or overwrite another account drafts',
    () async {
      var owner = 'alice';
      final queue = SupportTicketQueue.forTesting(ownerId: () => owner);
      await queue.upsertDraft(draft('private-alice'));
      owner = 'bob';
      expect(queue.drafts, isEmpty);
      await queue.ensureLoaded();
      expect(queue.drafts, isEmpty);
      await queue.upsertDraft(draft('private-bob'));
      owner = 'alice';
      expect(queue.drafts, isEmpty);
      await queue.ensureLoaded();
      expect(queue.drafts.single.id, 'private-alice');
      queue.dispose();
    },
  );

  test(
    'support mailto preserves distinct subject and body with special characters',
    () {
      final uri = supportEmailUri(
        subject: 'A & B = 1?',
        body: 'First line\nSecond + line & details',
      );
      expect(uri.scheme, 'mailto');
      expect(uri.queryParameters['subject'], 'A & B = 1?');
      expect(
        uri.queryParameters['body'],
        'First line\nSecond + line & details',
      );
      expect(uri.query, contains('&body='));
      expect(uri.query, isNot(contains('+')));
    },
  );

  test(
    'account deletion removes drafts and prevents late saves restoring them',
    () async {
      final queue = SupportTicketQueue.forTesting(
        ownerId: () => 'deleted-user',
      );
      await queue.upsertDraft(draft('private'));
      await queue.clearForUser('deleted-user');
      expect(queue.drafts, isEmpty);
      await expectLater(queue.upsertDraft(draft('late')), throwsStateError);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey('support.drafts.v1.deleted-user'),
        isFalse,
      );
      queue.dispose();
    },
  );

  for (final screen in <Widget>[
    const BusinessModeScreen(),
    const BusinessModeSetupScreen(),
    const BusinessProfileScreen(),
  ]) {
    testWidgets(
      '${screen.runtimeType} preserves restricted live access with usable local examples',
      (tester) async {
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();
        expect(find.byType(FeatureExampleScreen), findsOneWidget);
        expect(find.textContaining('INTERACTIVE EXAMPLE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'manual checklist persists checked steps across screen restarts',
    (tester) async {
      Widget screen() => const MaterialApp(
        home: ProgressChecklistScreen(
          title: 'Test mission',
          storageKey: 'widget-test',
          introduction: 'Manual observations',
          steps: [
            (title: 'Try discovery', detail: 'Use two devices.'),
            (title: 'Check support', detail: 'Submit a ticket.'),
          ],
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try discovery'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 completed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 completed'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isTrue,
      );
    },
  );

  testWidgets('guide search has useful topics and an actionable empty state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: UserGuideScreen()));
    await tester.enterText(find.byType(TextField), 'notification');
    await tester.pumpAndSettle();
    expect(find.text('Sounds and notifications'), findsOneWidget);
    expect(find.text('Get better nearby matches'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No topics found'), findsOneWidget);
  });

  testWidgets(
    'discovery simulator filters fictional profiles without Firebase',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DevUserSimulatorScreen()),
      );
      expect(find.text('1 matching examples'), findsOneWidget);
      await tester.tap(find.text('hiking'));
      await tester.pumpAndSettle();
      expect(find.text('2 matching examples'), findsOneWidget);
      await tester.tap(find.text('coffee'));
      await tester.tap(find.text('hiking'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No examples fit'), findsOneWidget);
    },
  );

  testWidgets('Pro example remains usable on a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: const FeatureExampleScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('INTERACTIVE EXAMPLE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Plan a promotion'), 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('points demo changes only its isolated example counter', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DevPointsDemoScreen()));
    await tester.tap(find.text('Add 25 examples'));
    await tester.pump();
    expect(find.text('25 example points'), findsOneWidget);
    await tester.tap(find.text('Spend 25 examples'));
    await tester.pump();
    expect(find.text('0 example points'), findsOneWidget);
  });

  testWidgets(
    'support destinations and practice remain available without progression data',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SupportHubScreen()));
      expect(find.text('Support center'), findsOneWidget);
      expect(find.text('My support tickets'), findsOneWidget);
      expect(find.text('My bug reports'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Community support practice'),
        200,
      );
      expect(find.text('Community support practice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
