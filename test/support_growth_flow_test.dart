import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prox/models/support_ticket_draft.dart';
import 'package:prox/screens/settings/support_feedback_screen.dart';
import 'package:prox/screens/support/support_ticket_screen.dart';
import 'package:prox/services/support_service.dart';
import 'package:prox/services/support_ticket_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'support metadata uses installed version/build and safe device model',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Prox',
        packageName: 'com.prox',
        version: '0.19.0',
        buildNumber: '26',
        buildSignature: 'test',
      );
      const channel = MethodChannel('prox/device_metadata');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => {'device': 'Google Pixel 8', 'os': 'Android 15'},
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final metadata = await SupportService.collectMetadata();
      expect(metadata['version'], '0.19.0');
      expect(metadata['build'], '26');
      expect(metadata['device'], 'Google Pixel 8');
      expect(metadata['os'], 'Android 15');
      expect(metadata.keys.toSet(), {
        'version',
        'build',
        'platform',
        'device',
        'os',
      });
    },
  );

  test('screenshot validation checks actual image signature and size', () {
    expect(
      () => SupportAttachment.fromBytes(Uint8List.fromList([1, 2, 3])),
      throwsArgumentError,
    );
    expect(
      () => SupportAttachment.fromBytes(
        Uint8List(SupportAttachment.maximumBytes + 1),
      ),
      throwsArgumentError,
    );
    final jpeg = SupportAttachment.fromBytes(
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
    );
    expect(jpeg.contentType, 'image/jpeg');
    expect(jpeg.extension, 'jpg');
    final png = SupportAttachment.fromBytes(
      Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    );
    expect(png.extension, 'png');
  });

  test(
    'saved support categories and confusion context survive reopen',
    () async {
      final queue = SupportTicketQueue.forTesting(ownerId: () => 'alice');
      await queue.upsertDraft(
        SupportTicketDraft(
          id: 'support_stable_id',
          subject: 'Refund question',
          message: 'Which checkout was charged?',
          createdAt: DateTime.utc(2026),
          category: 'billing',
          firstHuhMoment: 'The receipt was unclear.',
        ),
      );
      queue.dispose();
      final reopened = SupportTicketQueue.forTesting(ownerId: () => 'alice');
      await reopened.ensureLoaded();
      expect(reopened.drafts.single.id, 'support_stable_id');
      expect(reopened.drafts.single.category, 'billing');
      expect(reopened.drafts.single.firstHuhMoment, 'The receipt was unclear.');
      reopened.dispose();
    },
  );

  Future<void> largeScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
  }

  testWidgets(
    'categorized screenshot report freezes payload and ID across uncertain retry',
    (tester) async {
      final attempts = <SupportReportRequest>[];
      final image = SupportAttachment.fromBytes(
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
      );
      await largeScreen(
        tester,
        SupportFeedbackScreen(
          loadMetadata: () async => {
            'version': '0.19.0',
            'build': '26',
            'platform': 'android',
            'device': 'Pixel 8',
            'os': 'Android 15',
          },
          pickScreenshot: () async => image,
          submitReport: (report) async {
            attempts.add(report);
            if (attempts.length == 1) throw TimeoutException('lost response');
            return report.requestId;
          },
        ),
      );
      for (final label in [
        'Bug Report',
        'Usability',
        'Billing',
        'Feature idea',
        'Question',
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Billing'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'What is on your mind?'),
        'Checkout charged twice.',
      );
      await tester.ensureVisible(find.text('Attach screenshot (optional)'));
      await tester.tap(find.text('Attach screenshot (optional)'));
      await tester.pump();
      expect(find.text('Screenshot attached'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pump();
      expect(attempts, hasLength(1));
      expect(attempts.first.category, SupportCategory.billing);
      expect(attempts.first.metadata['build'], '26');
      expect(attempts.first.attachment, same(image));
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'What is on your mind?'),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pump();
      expect(attempts, hasLength(2));
      expect(attempts[1], same(attempts[0]));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Billing sent. Thank you.'), findsOneWidget);
      expect(find.text('Report received'), findsOneWidget);
    },
  );

  testWidgets(
    'ticket updates close the loop with exact fixed version and build',
    (tester) async {
      const ticket = TrackedSupportTicket(
        id: 'support_report_a',
        subject: 'Map jumps',
        message: 'The map jumps after reopening Nearby.',
        acknowledgement: 'Received. Support will review your report.',
      );
      final updates = StreamController<TrackedSupportTicket>();
      addTearDown(updates.close);
      await largeScreen(
        tester,
        SupportTicketScreen(
          ticket: ticket,
          ticketUpdates: updates.stream,
          replies: Stream.value([
            SupportReply(
              id: 'reply_1',
              message: 'We reproduced this issue.',
              fromSupport: true,
            ),
          ]),
          sendReply:
              ({
                required ticketId,
                required requestId,
                required message,
              }) async {},
        ),
      );
      expect(find.text('Received · question'), findsOneWidget);
      expect(find.text('We reproduced this issue.'), findsOneWidget);
      updates.add(
        const TrackedSupportTicket(
          id: 'support_report_a',
          subject: 'Map jumps',
          message: 'The map jumps after reopening Nearby.',
          status: 'resolved',
          fixedVersion: '0.20.0',
          fixedBuild: '27',
        ),
      );
      await tester.pump();
      expect(find.text('Resolved · question'), findsOneWidget);
      expect(find.text('Fixed in version 0.20.0, build 27'), findsOneWidget);
    },
  );

  testWidgets(
    'support reply retry preserves one request ID and the exact message',
    (tester) async {
      final attempts = <({String id, String message})>[];
      await largeScreen(
        tester,
        SupportTicketScreen(
          ticket: const TrackedSupportTicket(
            id: 'support_report_b',
            subject: 'Question',
            message: 'Can you help?',
          ),
          ticketUpdates: const Stream.empty(),
          replies: Stream.value([]),
          sendReply:
              ({
                required ticketId,
                required requestId,
                required message,
              }) async {
                attempts.add((id: requestId, message: message));
                if (attempts.length == 1)
                  throw TimeoutException('lost response');
              },
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Add a reply'),
        'It happens only in Listen Mode.',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Send reply'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send reply'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Add a reply'))
            .enabled,
        isFalse,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send reply'));
      await tester.pump();
      expect(attempts, hasLength(2));
      expect(attempts[0], attempts[1]);
      expect(find.text('Reply sent.'), findsOneWidget);
    },
  );
}
