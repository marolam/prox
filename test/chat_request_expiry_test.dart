import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/services/chat/chat_gate_service.dart';
import 'package:prox/services/chat/chat_request_policy.dart';
import 'package:prox/services/chat/chat_thread_service.dart';

Map<String, dynamic> request({
  String? mode = 'listen',
  int seconds = 86400,
  Duration age = const Duration(minutes: 2),
}) => {
  'participants': ['r5', 'zt'],
  'chatGate': <String, dynamic>{
    'status': 'requested',
    'requestedBy': 'zt',
    'requestedAt': Timestamp.fromDate(DateTime.now().subtract(age)),
    if (mode != null) 'modeKind': mode,
    if (mode != null) 'responseWindowSeconds': seconds,
  },
};

void main() {
  test('requested chats without a valid timestamp are treated as stale locally', () {
    final gate = ChatGateStatus.fromChatDoc({
      'chatGate': {'status': 'requested', 'requestedBy': 'zt'},
    });
    expect(gate.requestExpiredLocally, isTrue);
    expect(gate.isStaleOrExpired, isTrue);
  });

  test('requested chats past the active window are treated as stale locally', () {
    final gate = ChatGateStatus.fromChatDoc({
      'chatGate': {
        'status': 'requested',
        'requestedBy': 'zt',
        'modeKind': 'normal',
        'responseWindowSeconds': 60,
        'requestedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      },
    });
    expect(gate.requestExpiredLocally, isTrue);
    expect(gate.isStaleOrExpired, isTrue);
  });

  test('only a fresh Normal Active recipient gets a sixty-second window', () {
    final now = DateTime.now();
    final active = {
      'modeKind': 'normal',
      'normalMode': 'active',
      'ts': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(minutes: 3))),
    };
    expect(
      ChatRequestPolicy.creationWindow(MatchingModeKind.normal, active, now),
      const Duration(seconds: 60),
    );
    for (final mode in [
      MatchingModeKind.listen,
      MatchingModeKind.travel,
      MatchingModeKind.treasureHunt,
    ]) {
      expect(
        ChatRequestPolicy.creationWindow(mode, active, now),
        const Duration(hours: 24),
      );
    }
    expect(
      ChatRequestPolicy.creationWindow(MatchingModeKind.normal, {
        ...active,
        'normalMode': 'passive',
      }, now),
      const Duration(hours: 24),
    );
    expect(
      ChatRequestPolicy.creationWindow(
        MatchingModeKind.normal,
        active,
        now.add(const Duration(minutes: 4)),
      ),
      const Duration(hours: 24),
    );
  });

  for (final mode in ['listen', 'travel', null]) {
    test(
      '$mode requests stay available after sixty seconds without an Active countdown',
      () async {
        final db = FakeFirebaseFirestore();
        await db.doc('chats/r5_zt').set(request(mode: mode));
        var penalties = 0;
        final service = ChatGateService.forTesting(
          firestore: db,
          uidProvider: () => 'r5',
          activeProvider: () => true,
          onPenalty: () => penalties++,
        );
        expect(await service.watchIncomingRequestDeadline().first, isNull);
        await service.enforceExpiredIncomingRequestsIfNeeded();
        expect(
          (await db.doc('chats/r5_zt').get()).data()?['chatGate']['status'],
          'requested',
        );
        expect(penalties, 0);
        await service.accept(chatId: 'r5_zt', accepterUid: 'r5');
        expect(
          (await db.doc('chats/r5_zt').get()).data()?['chatGate']['status'],
          'accepted',
        );
      },
    );
  }

  test(
    'expired Active requests are handled once; expired Listen requests never cause an Active penalty',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('chats/active').set(request(mode: 'normal', seconds: 60));
      await db.doc('chats/listen').set(request(age: const Duration(hours: 25)));
      var penalties = 0;
      final service = ChatGateService.forTesting(
        firestore: db,
        uidProvider: () => 'r5',
        activeProvider: () => true,
        onPenalty: () => penalties++,
      );
      await service.enforceExpiredIncomingRequestsIfNeeded();
      expect(penalties, 1);
      for (final id in ['active', 'listen']) {
        expect(
          (await db.doc('chats/$id').get()).data()?['chatGate']['status'],
          'expired',
        );
      }
      await service.enforceExpiredIncomingRequestsIfNeeded();
      expect(penalties, 1);
      await expectLater(
        service.accept(chatId: 'active', accepterUid: 'r5'),
        throwsStateError,
      );
    },
  );

  test(
    'a timed-out request renews only on explicit action and clears old expiry metadata',
    () async {
      final db = FakeFirebaseFirestore();
      final old = request();
      (old['chatGate'] as Map<String, dynamic>).addAll({
        'status': 'expired',
        'expiredBySystem': true,
        'expiredAt': Timestamp.now(),
        'expiredForUid': 'r5',
      });
      await db.doc('chats/r5_zt').set(old);
      final service = ChatThreadService.forTesting(
        firestore: db,
        uidProvider: () => 'r5',
      );
      await service.ensureChat(
        myUid: 'r5',
        otherUid: 'zt',
        modeKind: MatchingModeKind.listen,
      );
      expect((await db.doc('chats/r5_zt').get()).data(), old);
      await service.ensureChat(
        myUid: 'r5',
        otherUid: 'zt',
        renewExpired: true,
        modeKind: MatchingModeKind.listen,
      );
      final renewed = (await db.doc('chats/r5_zt').get()).data()!;
      expect(renewed['participants'], ['r5', 'zt']);
      expect(renewed['chatGate']['status'], 'requested');
      expect(renewed['chatGate']['requestedBy'], 'r5');
      expect(renewed['chatGate']['responseWindowSeconds'], 86400);
      expect(
        (renewed['chatGate'] as Map<String, dynamic>).containsKey('expiredAt'),
        isFalse,
      );
    },
  );

  test(
    'renewal cannot undo a decline, accepted request, deliberate expiry or closed conversation',
    () async {
      final db = FakeFirebaseFirestore();
      final service = ChatThreadService.forTesting(
        firestore: db,
        uidProvider: () => 'r5',
      );
      for (final patch in [
        {'status': 'declined'},
        {'status': 'accepted'},
        {'status': 'expired'},
        {'status': 'expired', 'expiredBySystem': true, 'declinedBy': 'zt'},
        {'status': 'expired', 'expiredBySystem': true, 'acceptedBy': 'zt'},
      ]) {
        final before = request();
        (before['chatGate'] as Map<String, dynamic>).addAll(patch);
        await db.doc('chats/r5_zt').set(before);
        await service.ensureChat(
          myUid: 'r5',
          otherUid: 'zt',
          renewExpired: true,
          modeKind: MatchingModeKind.listen,
        );
        expect((await db.doc('chats/r5_zt').get()).data(), before);
      }
      final closed = request()..['closedAt'] = Timestamp.now();
      (closed['chatGate'] as Map<String, dynamic>).addAll({
        'status': 'expired',
        'expiredBySystem': true,
      });
      await db.doc('chats/r5_zt').set(closed);
      await service.ensureChat(
        myUid: 'r5',
        otherUid: 'zt',
        renewExpired: true,
        modeKind: MatchingModeKind.listen,
      );
      expect((await db.doc('chats/r5_zt').get()).data(), closed);
    },
  );
}
