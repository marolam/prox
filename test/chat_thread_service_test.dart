import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/chat/chat_thread_service.dart';

void main() {
  test(
    'the second participant opens the same chat without replacing its request',
    () async {
      final db = FakeFirebaseFirestore();
      var uid = 'zy';
      final service = ChatThreadService.forTesting(
        firestore: db,
        uidProvider: () => uid,
      );
      final first = await service.ensureChat(myUid: 'zy', otherUid: 'r5');
      final before = (await db.doc('chats/$first').get()).data();
      expect(before?['participants'], ['r5', 'zy']);
      expect(before?['chatGate']['requestedBy'], 'zy');
      uid = 'r5';
      expect(await service.ensureChat(myUid: 'r5', otherUid: 'zy'), first);
      expect((await db.doc('chats/$first').get()).data(), before);
    },
  );

  for (final status in ['requested', 'accepted', 'declined', 'expired']) {
    test(
      'opening an existing $status chat preserves legacy ordering and consent',
      () async {
        final db = FakeFirebaseFirestore();
        final before = {
          'participants': ['zy', 'r5'],
          'chatGate': {
            'status': status,
            'requestedBy': 'zy',
            'requestedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
          },
          'updatedAt': Timestamp.fromMillisecondsSinceEpoch(2000),
          'lastMessage': 'Existing conversation',
          if (status == 'expired')
            'closedAt': Timestamp.fromMillisecondsSinceEpoch(3000),
        };
        await db.doc('chats/r5_zy').set(before);
        final service = ChatThreadService.forTesting(
          firestore: db,
          uidProvider: () => 'r5',
        );
        expect(await service.ensureChat(myUid: 'r5', otherUid: 'zy'), 'r5_zy');
        expect((await db.doc('chats/r5_zy').get()).data(), before);
      },
    );
  }

  test(
    'another account or colliding pair cannot open or overwrite a chat',
    () async {
      final db = FakeFirebaseFirestore();
      var uid = 'r5';
      final service = ChatThreadService.forTesting(
        firestore: db,
        uidProvider: () => uid,
      );
      await expectLater(
        service.ensureChat(myUid: 'zy', otherUid: 'r5'),
        throwsStateError,
      );
      final original = {
        'participants': ['a', 'b_c'],
      };
      await db.doc('chats/a_b_c').set(original);
      uid = 'a_b';
      await expectLater(
        service.ensureChat(myUid: 'a_b', otherUid: 'c'),
        throwsStateError,
      );
      expect((await db.doc('chats/a_b_c').get()).data(), original);
    },
  );

  test('invalid or self-chat requests never create documents', () async {
    final db = FakeFirebaseFirestore();
    final service = ChatThreadService.forTesting(
      firestore: db,
      uidProvider: () => 'r5',
    );
    for (final peer in ['', 'r5', 'users/zy', ' zy ']) {
      await expectLater(
        service.ensureChat(myUid: 'r5', otherUid: peer),
        throwsArgumentError,
      );
    }
    expect((await db.collection('chats').get()).docs, isEmpty);
  });
}
