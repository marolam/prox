import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/support_ticket_draft.dart';
import 'package:prox/screens/settings/support_feedback_screen.dart';
import 'package:prox/screens/support/support_compose_screen.dart';
import 'package:prox/services/support_service.dart';
import 'package:prox/services/support_ticket_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final message = find.widgetWithText(TextField, 'What happened?');
  final submit = find.widgetWithText(FilledButton, 'Submit in app');

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  SupportTicketDraft draft() => SupportTicketDraft(
    id: '1791200100000',
    subject: 'test',
    message: 'test',
    createdAt: DateTime.utc(2026, 10, 5),
  );

  testWidgets('old short draft submits with metadata and keeps its report ID', (
    tester,
  ) async {
    final queue = SupportTicketQueue.forTesting(ownerId: () => 'alice');
    addTearDown(queue.dispose);
    final saved = draft();
    await queue.upsertDraft(saved);
    final attempts = <SupportReportRequest>[];
    await open(
      tester,
      SupportComposeScreen(
        existingDraft: saved,
        currentUid: () => 'alice',
        draftQueue: queue,
        loadMetadata: () async => {
          'version': '0.20.1',
          'build': '28',
          'platform': 'android',
          'device': 'Samsung SM-S901U',
        },
        submitReport: (report) async {
          attempts.add(report);
          expect(queue.drafts.single.id, saved.id);
          return report.requestId;
        },
      ),
    );
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Attach screenshot (optional)'), findsOneWidget);
    expect(find.textContaining('attached automatically'), findsOneWidget);
    await send(tester);
    expect(attempts.single.requestId, saved.id);
    expect(attempts.single.subject, 'test');
    expect(attempts.single.message, 'test');
    expect(attempts.single.category, SupportCategory.question);
    expect(attempts.single.expectedUid, 'alice');
    expect(attempts.single.metadata['build'], '28');
    expect(queue.drafts, isEmpty);
    expect(find.text('Support ticket submitted.'), findsOneWidget);
  });

  testWidgets(
    'uncertain delivery preserves the draft and exact retry payload',
    (tester) async {
      final queue = SupportTicketQueue.forTesting(ownerId: () => 'alice');
      addTearDown(queue.dispose);
      final saved = draft();
      final attempts = <SupportReportRequest>[];
      await open(
        tester,
        SupportComposeScreen(
          existingDraft: saved,
          currentUid: () => 'alice',
          draftQueue: queue,
          loadMetadata: () async => {},
          submitReport: (report) async {
            attempts.add(report);
            if (attempts.length == 1) throw TimeoutException('lost response');
            return report.requestId;
          },
        ),
      );
      await send(tester);
      expect(queue.drafts.single.message, 'test');
      expect(tester.widget<TextField>(message).enabled, isFalse);
      expect(find.textContaining('same report reference'), findsOneWidget);
      await send(tester);
      expect(attempts, hasLength(2));
      expect(attempts[1], same(attempts[0]));
      expect(queue.drafts, isEmpty);
    },
  );

  testWidgets('rejection after uncertain delivery keeps the original payload', (
    tester,
  ) async {
    final queue = SupportTicketQueue.forTesting(ownerId: () => 'alice');
    addTearDown(queue.dispose);
    final attempts = <SupportReportRequest>[];
    await open(
      tester,
      SupportComposeScreen(
        existingDraft: draft(),
        currentUid: () => 'alice',
        draftQueue: queue,
        loadMetadata: () async => {},
        submitReport: (report) async {
          attempts.add(report);
          if (attempts.length == 1) throw TimeoutException('lost response');
          if (attempts.length == 2) {
            throw FirebaseFunctionsException(
              code: 'unauthenticated',
              message: 'Token expired',
            );
          }
          return report.requestId;
        },
      ),
    );
    await send(tester);
    await send(tester);
    expect(tester.widget<TextField>(message).enabled, isFalse);
    expect(
      find.textContaining('earlier attempt may have arrived'),
      findsOneWidget,
    );
    expect(queue.drafts.single.id, attempts.first.requestId);
    await send(tester);
    expect(attempts, hasLength(3));
    expect(attempts[1], same(attempts[0]));
    expect(attempts[2], same(attempts[0]));
    expect(queue.drafts, isEmpty);
  });

  testWidgets('validation rejection allows edits without creating a new ID', (
    tester,
  ) async {
    final queue = SupportTicketQueue.forTesting(ownerId: () => 'alice');
    addTearDown(queue.dispose);
    final saved = draft();
    final attempts = <SupportReportRequest>[];
    await open(
      tester,
      SupportComposeScreen(
        existingDraft: saved,
        currentUid: () => 'alice',
        draftQueue: queue,
        loadMetadata: () async => {},
        submitReport: (report) async {
          attempts.add(report);
          if (attempts.length == 1) {
            throw FirebaseFunctionsException(
              code: 'invalid-argument',
              message: 'Private server diagnostic',
            );
          }
          return report.requestId;
        },
      ),
    );
    await send(tester);
    expect(find.textContaining('Check the subject'), findsOneWidget);
    expect(find.textContaining('Private server diagnostic'), findsNothing);
    expect(tester.widget<TextField>(message).enabled, isTrue);
    await tester.enterText(message, 'The dashboard fails after scrolling.');
    await send(tester);
    expect(attempts, hasLength(2));
    expect(attempts[1].requestId, attempts[0].requestId);
    expect(attempts[1].message, 'The dashboard fails after scrolling.');
    expect(queue.drafts, isEmpty);
  });

  testWidgets(
    'account change cannot send or remove the original private draft',
    (tester) async {
      var owner = 'alice';
      final queue = SupportTicketQueue.forTesting(ownerId: () => owner);
      addTearDown(queue.dispose);
      await queue.upsertDraft(draft());
      var calls = 0;
      await open(
        tester,
        SupportComposeScreen(
          existingDraft: draft(),
          currentUid: () => owner,
          draftQueue: queue,
          loadMetadata: () async => {},
          submitReport: (report) async {
            calls++;
            return report.requestId;
          },
        ),
      );
      owner = 'bob';
      await send(tester);
      expect(calls, 0);
      expect(
        find.text('Sign in to submit this support ticket.'),
        findsOneWidget,
      );
      owner = 'alice';
      await queue.ensureLoaded();
      expect(queue.drafts.single.id, draft().id);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('account switch during delivery preserves both accounts drafts', (
    tester,
  ) async {
    var owner = 'alice';
    final queue = SupportTicketQueue.forTesting(ownerId: () => owner);
    addTearDown(queue.dispose);
    await queue.upsertDraft(draft());
    owner = 'bob';
    await queue.upsertDraft(draft().copyWith(message: 'Bob private draft'));
    owner = 'alice';
    await queue.ensureLoaded();
    await open(
      tester,
      SupportComposeScreen(
        existingDraft: draft(),
        currentUid: () => owner,
        draftQueue: queue,
        loadMetadata: () async => {},
        submitReport: (report) async {
          owner = 'bob';
          return report.requestId;
        },
      ),
    );
    await send(tester);
    expect(find.text('Support ticket submitted.'), findsNothing);
    expect(find.textContaining('Return to the account'), findsOneWidget);
    await queue.ensureLoaded();
    expect(queue.drafts.single.message, 'Bob private draft');
    await expectLater(
      queue.removeDraft(draft().id, expectedOwner: 'alice'),
      throwsStateError,
    );
    expect(queue.drafts.single.message, 'Bob private draft');
    owner = 'alice';
    await queue.ensureLoaded();
    expect(queue.drafts.single.message, 'test');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('feedback validation rejection also permits a corrected retry', (
    tester,
  ) async {
    final attempts = <SupportReportRequest>[];
    await open(
      tester,
      SupportFeedbackScreen(
        loadMetadata: () async => {},
        submitReport: (report) async {
          attempts.add(report);
          if (attempts.length == 1) {
            throw FirebaseFunctionsException(
              code: 'invalid-argument',
              message: 'Invalid report',
            );
          }
          return report.requestId;
        },
      ),
    );
    final body = find.widgetWithText(TextField, 'What broke?');
    await tester.enterText(body, 'test');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check the subject'), findsOneWidget);
    expect(tester.widget<TextField>(body).enabled, isTrue);
    await tester.enterText(body, 'The dashboard fails after scrolling.');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(attempts[1].requestId, attempts[0].requestId);
    expect(attempts[1].message, 'The dashboard fails after scrolling.');
    expect(find.text('Report received'), findsOneWidget);
  });
}
