import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prox/services/growth_service.dart';
import 'package:prox/screens/review/growth_hub_screen.dart';
import 'package:prox/screens/dev/growth_ops_screen.dart';

const codeA = 'PROX-P-ABCDEF123456';
const codeB = 'PROX-P-123456ABCDEF';
Map<String, dynamic> snapshot({
  String stage = 'testers',
  bool enabled = true,
}) => {
  'config': {
    'enabled': enabled,
    'stage': stage,
    'testerCapacity': 20,
    'welcomePoints': 5,
    'referrerPoints': 10,
  },
  'tester': {},
  'progress': {},
  'referral': {},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only exact trusted referral links can save pilot attribution', () {
    for (final url in [
      'https://www.prox-us.com/referral.html?code=$codeA',
      'https://prox-us.com/?growth=$codeA',
      'prox://referral?code=$codeA',
    ]) {
      expect(GrowthService.referralCodeFromUri(Uri.parse(url)), codeA);
    }
    for (final url in [
      'http://prox-us.com/?growth=$codeA',
      'https://prox-us.com.evil.test/?growth=$codeA',
      'https://user@prox-us.com/?growth=$codeA',
      'https://prox-us.com:444/?growth=$codeA',
      'https://prox-us.com/support.html?growth=$codeA',
      'prox://other?code=$codeA',
      'https://prox-us.com/?growth=../../users',
      'https://prox-us.com/?code=LEGACY123',
    ]) {
      expect(
        GrowthService.referralCodeFromUri(Uri.parse(url)),
        isNull,
        reason: url,
      );
    }
  });

  test(
    'queue pressure evicts a whole session and retains later session starts',
    () {
      final queue = <Map<String, dynamic>>[
        {'sessionId': 'old', 'event': 'start'},
        for (var i = 0; i < 95; i++) {'sessionId': 'old', 'event': 'error'},
        {'sessionId': 'new', 'event': 'start'},
        for (var i = 0; i < 6; i++) {'sessionId': 'new', 'event': 'error'},
      ];
      GrowthService.trimSessionQueue(queue);
      expect(queue.every((entry) => entry['sessionId'] == 'new'), isTrue);
      expect(queue.first['event'], 'start');
      expect(queue, hasLength(7));
    },
  );

  test('an orphan outcome cannot block a later valid session', () async {
    SharedPreferences.setMockInitialValues({
      'growth.pendingSessions.v1.alice':
          '[{"requestId":"orphan_1","sessionId":"orphan_session","event":"end"},'
          '{"requestId":"valid_1","sessionId":"valid_session","event":"start"}]',
    });
    final reported = <String>[];
    final service = GrowthService.forTesting(
      caller: (name, data) async {
        if (name == 'recordGrowthSession') {
          reported.add(data['sessionId'] as String);
          if (data['sessionId'] == 'orphan_session') {
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'Start session first',
            );
          }
          return {'recorded': true};
        }
        return snapshot();
      },
    );
    await service.bindAccount('alice');
    await service.flushPendingSessions();
    expect(reported, ['orphan_session', 'valid_session']);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'growth.pendingSessions.v1.alice',
      ),
      '[]',
    );
    service.dispose();
  });

  test(
    'a permanently expired referral clears so a new valid link can apply',
    () async {
      final accepted = <String>[];
      final service = GrowthService.forTesting(
        caller: (name, data) async {
          if (name == 'acceptGrowthReferral') {
            accepted.add(data['code'] as String);
            if (data['code'] == codeA) {
              throw FirebaseFunctionsException(
                code: 'failed-precondition',
                message: 'This invite has expired or was used.',
              );
            }
            return {'linked': true};
          }
          return snapshot(stage: 'referrals');
        },
      );
      await service.captureReferral(Uri.parse('prox://referral?code=$codeA'));
      await service.bindAccount('alice');
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'growth.pendingReferral.v1',
        ),
        isFalse,
      );
      await service.captureReferral(Uri.parse('prox://referral?code=$codeB'));
      expect(accepted, [codeA, codeB]);
      service.dispose();
    },
  );

  test(
    'a late account response cannot expose previous account progress',
    () async {
      final old = Completer<Map<String, dynamic>>();
      var count = 0;
      final service = GrowthService.forTesting(
        caller: (name, data) async {
          if (name == 'getGrowthStatus' && ++count == 1) return old.future;
          return {...snapshot(), 'accountMarker': 'bob'};
        },
      );
      final firstBind = service.bindAccount('alice');
      await Future<void>.delayed(Duration.zero);
      await service.bindAccount('bob');
      old.complete({...snapshot(), 'accountMarker': 'alice'});
      await firstBind;
      expect(service.uid, 'bob');
      expect(service.status!.data['accountMarker'], 'bob');
      expect(service.lastError, isNull);
      service.dispose();
    },
  );

  test(
    'first captured invite and stable request survive failure and retry',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = GrowthService.forTesting(
        caller: (name, data) async {
          if (name == 'acceptGrowthReferral') {
            requests.add(Map.of(data));
            if (requests.length == 1) throw StateError('offline');
            return {'accepted': true};
          }
          return snapshot(stage: 'referrals');
        },
      );
      await service.captureReferral(
        Uri.parse('https://prox-us.com/?growth=$codeA'),
      );
      await service.captureReferral(
        Uri.parse('https://prox-us.com/?growth=$codeB'),
      );
      await service.bindAccount('alice');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('growth.pendingReferral.v1'), codeA);
      await service.captureReferral(
        Uri.parse('https://prox-us.com/?growth=$codeB'),
      );
      expect(requests, hasLength(2));
      expect(requests.every((request) => request['code'] == codeA), isTrue);
      expect(requests[0]['requestId'], requests[1]['requestId']);
      expect(requests[0]['deviceId'], requests[1]['deviceId']);
      expect(preferences.containsKey('growth.pendingReferral.v1'), isFalse);
      service.dispose();
    },
  );

  test(
    'tester stage retains pending invite without releasing a reward',
    () async {
      var accepts = 0;
      final service = GrowthService.forTesting(
        caller: (name, data) async {
          if (name == 'acceptGrowthReferral') accepts++;
          return snapshot();
        },
      );
      await service.captureReferral(Uri.parse('prox://referral?code=$codeA'));
      await service.bindAccount('alice');
      expect(accepts, 0);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'growth.pendingReferral.v1',
        ),
        codeA,
      );
      service.dispose();
    },
  );

  test(
    'account deletion clears telemetry and forbids late account calls',
    () async {
      SharedPreferences.setMockInitialValues({
        'growth.pendingSessions.v1.alice': '[{"event":"error"}]',
        'growth.pendingSessions.v1.bob': '[{"event":"start"}]',
      });
      final service = GrowthService.forTesting(
        caller: (name, data) async => snapshot(),
      );
      await service.bindAccount('alice');
      await service.clearForUser('alice');
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey('growth.pendingSessions.v1.alice'),
        isFalse,
      );
      expect(preferences.containsKey('growth.pendingSessions.v1.bob'), isTrue);
      await expectLater(service.call('getGrowthStatus'), throwsStateError);
      service.dispose();
    },
  );

  testWidgets(
    'pilot mission shows admin approval and cannot self-complete actions',
    (tester) async {
      final service = GrowthService.forTesting(
        caller: (name, data) async => {
          ...snapshot(),
          'tester': {'status': 'pending'},
        },
      );
      await service.bindAccount('alice');
      await tester.pumpWidget(
        MaterialApp(home: GrowthHubScreen(service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Application received'), findsOneWidget);
      expect(find.textContaining('Referral rewards open'), findsOneWidget);
      expect(find.text('Create referral link'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );

  testWidgets('ops denied requests show a recoverable error without data', (
    tester,
  ) async {
    final service = GrowthService.forTesting(
      caller: (name, data) async {
        if (name == 'getGrowthOps') throw StateError('not admin');
        return snapshot();
      },
    );
    await service.bindAccount('alice');
    await tester.pumpWidget(
      MaterialApp(home: GrowthOpsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Operations request failed. Please retry.'),
      findsOneWidget,
    );
    expect(find.text('Daily metrics'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('account switch removes cached private operations data', (
    tester,
  ) async {
    final service = GrowthService.forTesting(
      caller: (name, data) async => name == 'getGrowthOps'
          ? {
              'config': snapshot()['config'],
              'metrics': [],
              'tickets': [
                {
                  'id': 'ticket_private_1',
                  'uid': 'reporter',
                  'subject': 'Private report',
                  'category': 'bug',
                  'severity': 'P1',
                  'status': 'open',
                },
              ],
            }
          : snapshot(),
    );
    await service.bindAccount('admin');
    await tester.pumpWidget(
      MaterialApp(home: GrowthOpsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Private report'), findsOneWidget);
    await service.bindAccount('bob');
    await tester.pumpAndSettle();
    expect(find.textContaining('Private report'), findsNothing);
    expect(find.textContaining('Account changed.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
