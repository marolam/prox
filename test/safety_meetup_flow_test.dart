import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/safety_session_service.dart';
import 'package:prox/widgets/safety_access_shell.dart';
import 'package:prox/widgets/meetup_progress_card.dart';

void main() {
  const session = SafetySession(
    id: 'chat',
    otherUid: 'Bob',
    hasMeetup: true,
    hasChat: true,
  );
  testWidgets(
    'Safety remains above dialogs; emergency dialing is two taps and preserves the route',
    (tester) async {
      var calls = 0;
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          builder: (context, child) => SafetyAccessShell(
            loadSessions: () => Stream.value([]),
            openPhone: () async {
              calls++;
              return true;
            },
            child: child!,
          ),
          home: const Scaffold(body: Text('Underlying page')),
        ),
      );
      showDialog<void>(
        context: navKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Another dialog')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Safety'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open phone to call 911 (US)'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Close Safety'));
      await tester.pumpAndSettle();
      expect(find.text('Another dialog'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening Safety does not cancel; the explicit confirmation ends the selected session',
    (tester) async {
      final ended = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => SafetyAccessShell(
            loadSessions: () => Stream.value([session]),
            endSession: (id, all) async => ended.add('$id:$all'),
            openPhone: () async => true,
            child: child!,
          ),
          home: const Scaffold(),
        ),
      );
      await tester.tap(find.text('Safety'));
      await tester.pumpAndSettle();
      expect(ended, isEmpty);
      await tester.ensureVisible(find.text('Confirm: end chat & meetup'));
      await tester.tap(find.text('Confirm: end chat & meetup'));
      await tester.pumpAndSettle();
      expect(ended, ['chat:true']);
      expect(
        find.text('Chat ended. Any active meetup was cancelled.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'cancellation failure stays actionable and never blocks the emergency action',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafetyPanel(
              sessions: Stream.value([session]),
              endSession: (_, _) async => throw StateError('offline'),
              openPhone: () async {
                calls++;
                return false;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm: cancel meetup'));
      await tester.tap(find.text('Confirm: cancel meetup'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cancellation has not been confirmed'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Open phone to call 911 (US)'));
      await tester.tap(find.text('Open phone to call 911 (US)'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.textContaining('Could not open the phone app'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pending cancellation disables duplicate submissions but leaves emergency dialing enabled',
    (tester) async {
      final pending = Completer<void>();
      var ended = 0;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafetyPanel(
              sessions: Stream.value([session]),
              endSession: (_, _) {
                ended++;
                return pending.future;
              },
              openPhone: () async {
                calls++;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm: cancel meetup'));
      await tester.tap(find.text('Confirm: cancel meetup'));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Confirm: cancel meetup'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Open phone to call 911 (US)'));
      await tester.tap(find.text('Open phone to call 911 (US)'));
      await tester.pump();
      expect(calls, 1);
      expect(ended, 1);
      pending.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'guidance identifies planner, traveler, waiting arrival and definite terminal outcomes',
    (tester) async {
      Future<void> show(Map<String, dynamic> data) async => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MeetupProgressCard(data: data, uid: 'alice'),
            ),
          ),
        ),
      );
      final data = <String, dynamic>{
        'status': 'live',
        'aUid': 'alice',
        'bUid': 'bob',
        'plannerUid': 'alice',
      };
      await show(data);
      expect(find.text('Step 2 of 4 · Choose a meeting point'), findsOneWidget);
      await show({...data, 'lat': 1, 'lng': 1});
      expect(
        find.textContaining('Wait for the other person to confirm'),
        findsOneWidget,
      );
      await show({...data, 'locationStatus': 'confirmed', 'lat': 1, 'lng': 1});
      expect(
        find.textContaining('Opening Maps does not confirm your arrival'),
        findsOneWidget,
      );
      await show({
        ...data,
        'locationStatus': 'confirmed',
        'lat': 1,
        'lng': 1,
        'aArrived': true,
      });
      expect(
        find.text('Step 4 of 4 · Waiting for their arrival'),
        findsOneWidget,
      );
      await show({...data, 'status': 'auto_closed'});
      expect(find.text('Meetup ended without completion'), findsOneWidget);
      await show({...data, 'status': 'cancelled'});
      expect(find.text('Meetup cancelled'), findsOneWidget);
      expect(find.textContaining('deadline'), findsNothing);
    },
  );
}
